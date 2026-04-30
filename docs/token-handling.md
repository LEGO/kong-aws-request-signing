# Token Handling in `aws-request-signing`

This document describes exactly how the `aws-request-signing` Kong plugin
handles tokens — both the **inbound** bearer token (typically an OIDC JWT) and
the **outbound** AWS SigV4 credentials it produces. It also lists the JWT
claims that are relevant in the end‑to‑end flow, even though most of them are
validated by AWS rather than by the plugin itself.

> **TL;DR**
> - The plugin treats the inbound bearer token as **opaque** — it does **not**
>   decode or validate any JWT claim. Claim validation is performed by **AWS
>   STS** and the **IAM role trust policy**.
> - The inbound token is forwarded to `sts:AssumeRoleWithWebIdentity` as the
>   `WebIdentityToken` parameter.
> - The original `Authorization` header is (by default) preserved verbatim on
>   `x-authorization` and then removed from the upstream request.
> - The **outbound `Authorization` header is not a JWT** — it is an
>   `AWS4-HMAC-SHA256` SigV4 signature constructed from temporary STS
>   credentials.

---

## 1. Request flow

```
   Client                  Kong (aws-request-signing)                AWS STS              Upstream (e.g. Lambda / API GW)
     │                                │                                  │                              │
     │  Authorization: Bearer <JWT>   │                                  │                              │
     │ ──────────────────────────────▶│                                  │                              │
     │                                │   AssumeRoleWithWebIdentity      │                              │
     │                                │   WebIdentityToken=<JWT>         │                              │
     │                                │ ────────────────────────────────▶│                              │
     │                                │   {AccessKey, Secret, Session}   │                              │
     │                                │ ◀────────────────────────────────│                              │
     │                                │                                  │                              │
     │                                │  x-authorization: Bearer <JWT>   (preserved copy, optional)     │
     │                                │  Authorization: AWS4-HMAC-SHA256 Credential=…, Signature=…      │
     │                                │  x-amz-date, x-amz-security-token, x-amz-content-sha256, host   │
     │                                │ ──────────────────────────────────────────────────────────────▶│
```

---

## 2. Inbound token

### 2.1 Where the plugin reads it from

| Aspect            | Value                                                        |
| ----------------- | ------------------------------------------------------------ |
| Source header     | Configurable via `auth_header` (default: `authorization`)    |
| Expected format   | `Bearer <token>` (case‑insensitive, leading/trailing spaces tolerated) |
| Extraction regex  | `\s* Bearer \s+ (.+)` (see [handler.lua](../kong/plugins/aws-request-signing/handler.lua)) |
| Behavior if missing | Plugin logs a notice and **returns without signing** (request is forwarded unchanged). |

### 2.2 What the plugin does with it

The plugin **does not parse, decode, or validate** the JWT. It extracts the
substring after `Bearer ` and uses it directly as the `WebIdentityToken` query
parameter on the call to AWS STS:

```
GET https://sts.amazonaws.com/?
        Action=AssumeRoleWithWebIdentity
       &RoleArn=<aws_assume_role_arn or arn built from aws_account_id+aws_assume_role_name>
       &RoleSessionName=<aws_assume_role_name>
       &DurationSeconds=3600
       &Version=2011-06-15
       &WebIdentityToken=<the bearer token verbatim>
```

This is implemented in
[`webidentity-sts-credentials.lua`](../kong/plugins/aws-request-signing/webidentity-sts-credentials.lua).

### 2.3 JWT claims that matter in the flow

Although the plugin never reads them, AWS STS and the IAM role trust policy
**do** validate the following JWT claims. A misconfiguration in any of them is
the most common reason `AssumeRoleWithWebIdentity` fails.

| Claim         | Validated by                               | Purpose / typical configuration |
| ------------- | ------------------------------------------ | ------------------------------- |
| `iss`         | AWS STS (against the configured OIDC IdP)  | Must match an IAM Identity Provider registered in the AWS account. |
| `aud` / `client_id` | IAM role trust policy (`StringEquals`) | Must match the audience expected by the role’s trust policy condition (e.g. `<provider>:aud`). |
| `sub`         | IAM role trust policy (`StringEquals` / `StringLike`) | Often pinned to a specific subject (user / service account / GitHub repo, etc.). Also becomes part of the assumed‑role session identity. |
| `azp`         | IAM role trust policy (provider‑specific)  | Some IdPs (e.g. Google) require `azp` matching in the trust condition. |
| `exp`         | AWS STS                                    | Token must not be expired. |
| `nbf`         | AWS STS                                    | Token must be valid “now”. |
| `iat`         | AWS STS                                    | Issuance time sanity check. |
| `jti`, custom | Not used                                   | Ignored unless your IdP/IAM trust policy explicitly references them. |

> The plugin does **not** verify the JWT signature. AWS STS does, by fetching
> the JWKS from the OIDC issuer (`iss`).

### 2.4 Caching behavior

Temporary STS credentials are cached in Kong’s shared cache:

- **Cache key:** `plugin.aws-request-signing.iam_role_temp_creds.<RoleArn>`
- **TTL:** until 60 s before `Expiration` returned by STS.
- **Force refresh:** send the request header `x-sts-refresh` (any value) to
  invalidate the local cache entry before fetching credentials.

Because the cache key only includes the **role ARN**, two requests carrying
different inbound JWTs that resolve to the **same role** will share the same
cached STS credentials for the cache lifetime. The inbound JWT is only
re‑exchanged with STS when the cache is cold, expired, or explicitly
refreshed.

---

## 3. Preserving the original token

By default, the original `Authorization` header is copied to a separate header
on the upstream request before being removed. This lets the upstream service
(e.g. a Lambda) still see the caller’s identity if it needs to.

| Config key                  | Default            | Effect                                                                 |
| --------------------------- | ------------------ | ---------------------------------------------------------------------- |
| `preserve_auth_header`      | `true`             | If `true`, copy the original auth header value to `preserve_auth_header_key` before clearing it. |
| `preserve_auth_header_key`  | `x-authorization`  | Destination header name for the preserved value.                       |
| `auth_header`               | `authorization`    | Source header name (the one carrying `Bearer <token>`).                |

The preserved value is **verbatim**, including the `Bearer ` prefix. The
plugin does not strip, decode, or modify it.

Order of operations on the upstream request:

1. Copy original `auth_header` value → `preserve_auth_header_key` (if enabled).
2. Clear the original `auth_header` from the upstream request.
3. After SigV4 signing, set the **new** `authorization` header (or query
   parameters, if `sign_query=true`).

---

## 4. Outbound request (SigV4, not a JWT)

The outbound `Authorization` header produced by the plugin is an AWS SigV4
v4 signature, **not** a JWT. There is no JSON payload, no claims, and no
base64‑encoded segments — it is an HMAC‑SHA256 signature over a canonicalized
request. See [`sigv4.lua`](../kong/plugins/aws-request-signing/sigv4.lua).

### 4.1 Header signing mode (`sign_query = false`, default)

The plugin sets the following headers on the upstream request:

| Header                  | Value                                                                                                                                          |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `authorization`         | `AWS4-HMAC-SHA256 Credential=<AccessKeyId>/<yyyymmdd>/<region>/<service>/aws4_request, SignedHeaders=<list>, Signature=<hex>`                  |
| `x-amz-date`            | `yyyymmddTHHMMSSZ` — request timestamp.                                                                                                        |
| `x-amz-security-token`  | The STS `SessionToken` (only present because credentials are temporary).                                                                       |
| `x-amz-content-sha256`  | Hex SHA‑256 of the raw request body.                                                                                                           |
| `host`                  | Recomputed from the (possibly overridden) target host/port. Port is appended unless it is 80 or 443.                                           |
| `content-length`        | Passed through from the inbound request **if present** — included in the signature.                                                            |
| `content-type`          | Passed through from the inbound request **if present** — included in the signature.                                                            |
| `x-amz-expires`         | `300` — only added when `aws_service = "s3"`.                                                                                                  |

Notes:

- Only `host`, `content-length`, `content-type`, plus the `x-amz-*` headers
  added by the signer, are part of `SignedHeaders`. **Other inbound headers
  are not included in the signature** (although they are still forwarded as
  normal Kong upstream headers).
- The original inbound `authorization` header is removed from the upstream
  request before the new SigV4 `authorization` header is set.

### 4.2 Query signing mode (`sign_query = true`)

Instead of signing via headers, the signature and metadata are appended to
the upstream query string:

| Query parameter         | Value                                                                                  |
| ----------------------- | -------------------------------------------------------------------------------------- |
| `X-Amz-Algorithm`       | `AWS4-HMAC-SHA256`                                                                     |
| `X-Amz-Credential`      | `<AccessKeyId>/<yyyymmdd>/<region>/<service>/aws4_request` (URL‑encoded by AWS clients) |
| `X-Amz-Date`            | `yyyymmddTHHMMSSZ`                                                                     |
| `X-Amz-SignedHeaders`   | Semicolon‑separated, lowercased list of signed headers.                                |
| `X-Amz-Security-Token`  | URL‑encoded STS `SessionToken`.                                                        |
| `X-Amz-Signature`       | Hex HMAC‑SHA256 signature.                                                             |
| `X-Amz-Expires`         | `300` — only added when `aws_service = "s3"`.                                          |

In query mode, `x-amz-date` and `x-amz-security-token` are **not** added as
headers; their query‑string equivalents are used instead.

---

## 5. STS exchange details

Implemented in
[`webidentity-sts-credentials.lua`](../kong/plugins/aws-request-signing/webidentity-sts-credentials.lua).

| Aspect                  | Value                                                       |
| ----------------------- | ----------------------------------------------------------- |
| Endpoint                | `https://sts.amazonaws.com`                                 |
| HTTP method             | `GET` (parameters in query string)                          |
| Action                  | `AssumeRoleWithWebIdentity`                                 |
| API version             | `2011-06-15`                                                |
| `DurationSeconds`       | `3600` (1 hour) — hard‑coded                                |
| `RoleArn`               | `aws_assume_role_arn`, or built as `arn:aws:iam::<aws_account_id>:role/<aws_assume_role_name>` |
| `RoleSessionName`       | `aws_assume_role_name`                                      |
| `WebIdentityToken`      | The bearer token extracted from the inbound auth header     |
| Response fields used    | `AccessKeyId`, `SecretAccessKey`, `SessionToken`, `Expiration` |
| HTTP timeout            | 60 s                                                        |
| TLS verify              | Disabled (`ssl_verify = false`)                             |

If STS returns a non‑200 response and `return_aws_sts_error = true`, the
upstream STS status code and body are surfaced in the response to the client
(useful for debugging trust policy / audience mismatches). Otherwise, the
plugin returns `401` with a generic message.

---

## 6. Header summary: inbound vs outbound

| Header                      | Inbound (from client)        | Outbound (to upstream)                                                       |
| --------------------------- | ---------------------------- | ---------------------------------------------------------------------------- |
| `authorization` (or `auth_header`) | `Bearer <JWT>` (consumed)    | **Removed**, then replaced with `AWS4-HMAC-SHA256 …` (header mode only).     |
| `x-authorization` (or `preserve_auth_header_key`) | —                            | Verbatim copy of original `Bearer <JWT>` (when `preserve_auth_header=true`). |
| `host`                      | Original host                | Rewritten to signed target (with port unless 80/443). Part of signature.     |
| `content-type`              | Pass‑through                 | Pass‑through, included in signature if present.                              |
| `content-length`            | Pass‑through                 | Pass‑through, included in signature if present.                              |
| `x-amz-date`                | —                            | Added (header mode).                                                         |
| `x-amz-security-token`      | —                            | Added (header mode).                                                         |
| `x-amz-content-sha256`      | —                            | Added (always, header mode).                                                 |
| `x-amz-expires`             | —                            | Added (header mode, S3 only).                                                |
| `x-sts-refresh`             | Optional control header      | Not forwarded as a SigV4 concern; only triggers STS cache invalidation.      |

---

## 7. Notes & gotchas

- **No JWT verification in Kong.** If a malformed or expired JWT reaches the
  plugin, the failure surfaces as an STS error, not as a local validation
  error. Use `return_aws_sts_error = true` in non‑production environments to
  see the underlying STS message (`InvalidIdentityToken`, `ExpiredToken`,
  audience mismatch, etc.).
- **No `Authorization` header → no signing.** If the inbound request has no
  `auth_header`, the plugin logs a notice and forwards the request unchanged.
  It does **not** attempt to sign with a default credential chain.
- **Cache reuse.** Because STS credentials are cached per role ARN, a fresh
  inbound JWT does not by itself trigger a new STS exchange while cached
  credentials are valid. Use `x-sts-refresh` to force a refresh.
- **Body buffering.** The full request body is read for the SigV4 body hash
  and is therefore subject to
  `nginx_http_client_max_body_size` / `nginx_http_client_body_buffer_size`.
  Requests exceeding those limits are rejected with HTTP 400.
- **Path / query encoding.** Path canonicalization differs slightly when
  `aws_service = "lambda"` (uses `url_encode` on each segment) vs. other
  services. This matches AWS Lambda’s expected canonical form.
