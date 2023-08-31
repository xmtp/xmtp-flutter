## 1.2.1
- fix: make topics actually deterministic in all directions

## 1.2.0
- feat: implement codecs for attachment, reaction, and reply
- fix: batch paginate across multiple queries 
- fix: list all conversations across multiple query pages
- fix: join with comma to fix deterministic invites
- feat: support out-of-band decryption of conversation/message envelopes 

## 1.1.0
- feat: use deterministic topic/keyMaterial invite generation
- fix: discard messages from unsupported codecs when they have no fallback
- fix: partition batch calls to fit max size 

## 1.0.0
- General Availability release
- Fix for publishing v1 contact bundle signatures

## 0.0.4
- publish package with GitHub Actions
- use batch query for listing messages

## 0.0.3
- use batch query for listing messages

## 0.0.2-development
- signature check fixes
- additional performance updates

## 0.0.1-development.1
- initial Developer Preview
