# Home Assistant batch approval checks

Local checks on the project extension used `node --test tests/pi-home-assistant.test.ts`. All seven tests passed. The mock server checked that one approval sent two staged requests in order. An old ID, a repeated ID, and a reply from an RPC client or extension sent nothing. Cancellation and a Pi transcript branch change also sent nothing.

A mock HTTP 504 stopped the batch after its first request. The test counted one request to the server and no retry. Queue tests covered expiry, duplicate requests, the size limit, and a request with a credential.

Strict TypeScript passed against the installed Pi and `pi-tui` 1.6.0 declarations. The mock checks did not send any request to a live Home Assistant device.
