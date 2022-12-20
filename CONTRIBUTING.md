# Contributing

If you're seeing this document, you are an early contributor to the development and success of XMTP. Your questions, feedback, suggestions, and code contributions are welcome!

## ❔ Questions

Have a question? You are welcome to ask it in [Q&A discussions](https://github.com/orgs/xmtp/discussions/categories/q-a).

## 🐞 Bugs

Report bugs as GitHub Issues. Please confirm that there isn't an existing open issue about the bug and include detailed steps to reproduce the bug.

## ✨ Feature requests

Submit feature requests as GitHub Issues. Please confirm that there isn't an existing open issue requesting the feature. Describe the use cases this feature unlocks so the issue can be investigated and prioritized.

## 🔀 Pull requests

PRs are encouraged, but consider starting with a feature request to temperature-check first. If the PR involves a major change to the protocol, the work should be fleshed out as an [XMTP Improvement Proposal](https://github.com/xmtp/XIPs/blob/main/XIPs/xip-0-purpose-process.md) before work begins.

## 🔧 Developing

You'll usually want to run a local XMTP node to test and use your app in isolation.

Once you have [docker installed](https://docs.docker.com/get-docker/) you can run a local node
with the following command from inside `tool/local-node`:
```
$ docker-compose -p xmtp -f docker-compose.yml up
```
