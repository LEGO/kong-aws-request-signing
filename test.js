import http from 'k6/http';
import { check, group, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '10s', target: 2000 }, // below normal load
    { duration: '20s', target: 2000 },
    { duration: '30s', target: 3000 }, // normal load
    { duration: '20s', target: 4000 }, // around the breaking point
    { duration: '30s', target: 5000 }, // beyond the breaking point
    { duration: '15s', target: 6000 },
    { duration: '10s', target: 0 }, // scale down. Recovery stage.
  ],
  thresholds: {
    'http_req_duration': ['p(99)<1500'], // 99% of requests must complete below 1.5s
    'logged in successfully': ['p(99)<1500'], // 99% of requests must complete below 1.5s
  },
};

const BASE_URL_KONG = 'https://dev.api.legogroup.io/lambda';
const BASE_URL_AWS_GATEWAY = 'https://915yn6txz5.execute-api.eu-west-1.amazonaws.com/lambda';
const token = "azure token"
export default () => {
  const opts = {
    headers: {
        Authorization: `Bearer ${token}`,
    }
  };
  const body = JSON.stringify({
    name: "lambda-test",
    type: "manual",
    test_tool: "k6",
    test_executor: "dkDanRai"
})

  const res = http.post(`${BASE_URL_KONG}?some=1`, body, opts).json();
  // console.log(JSON.stringify(res))
  sleep(1);
};
