import http from 'k6/http';
import { check, group, sleep } from 'k6';

const maxVirtualUsers = 5200;

export const options = {
  stages: 
  [
    { duration: '5s', target: maxVirtualUsers }, // fast scale up to max
    { duration: '125s', target: maxVirtualUsers }, // stay for some time at max level
    { duration: '5s', target: 0 }, // scale down. Recovery stage.
  ],
  thresholds: {
    'http_req_duration': ['p(99)<1500'], // 99% of requests must complete below 1.5s
  },
};

const BASE_URL_KONG = 'https://kong.example.com/lambda';
const BASE_URL_AWS_GATEWAY = 'https://gateway.example.com/lambda';

const token = "A VALID AZURE TOKEN WITH THE AUDIENCE YOU ADDED IN WEBIDENTITY PROVIDER IN AWS"

const BASE_URL_TEST = BASE_URL_KONG

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
    test_executor: "YOUR NAME"
  })

  let res, json
  try {
    res = http.post(`${BASE_URL_TEST}?some=1`, body, opts);
    json = res.json()
  } catch (error) {
    console.log("FailedBody")
  }

  sleep(0.18);
};
