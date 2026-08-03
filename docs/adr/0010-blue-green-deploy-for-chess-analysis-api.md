# chess-analysis-api deploys blue-green, not PM2 cluster mode

We wanted zero-downtime deploys for `server` (a plain `pm2 restart` has a
real gap - it takes ~9s to become ready again after DB connections
establish, during which requests fail). PM2 cluster mode (2+ instances,
`pm2 reload`) was the first choice, but the app uses socket.io with custom
in-memory state (`workersIo`/`usersIo` arrays in `src/sockets/initSockets.ts`,
backing `isWorkerOnline()` - almost certainly what gates dispatching a
chess-analysis job to `worker1`). Socket.io's official Redis adapter fixes
cross-instance *broadcast* mechanics, but does nothing for this kind of
custom application-level state - with 2 cluster instances, a worker could
connect to instance A while an "is this worker online?" check lands on
instance B and incorrectly says no. Properly fixing that means refactoring
the worker-tracking to live in Redis instead of a local array - a real
change to core dispatch logic that deserves its own review, not something
to bundle into an infra migration.

Blue-green sidesteps the whole problem: only one instance is ever live at a
time (no split-brain state), so nothing about the app needed to change.
Two full checkouts (`/opt/apps/chess-analysis-api-blue` and `-green`, ports
8080/8081) sit side by side; `scripts` (well, `/opt/apps/chess-analysis-api-deploy.sh`
on the droplet, since this one is a locally-restricted-key CI script rather
than a `scripts/*.sh`) deploys to whichever is currently idle, health-checks
it, and only then flips nginx's `$api_backend` (an `include`d file,
`/etc/nginx/chess-analysis-api-active.conf`) to point at it - the previously
active color becomes idle, ready for the next deploy.

Redis was installed on the droplet as part of evaluating the cluster-mode
path and is currently unused - left in place (capped at 64MB) in case the
worker-tracking refactor happens later and actually needs it, rather than
installing and removing it twice.
