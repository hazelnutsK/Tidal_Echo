# Tidal Echo iOS build source

This branch contains published iOS source, tests, assets and the manual build workflow.
The server backend, credentials, conversations and other private runtime data are excluded.

Build: Actions -> iOS Build -> Run workflow -> choose ios-build.
Pushing a source snapshot does not start a build. The source-manifest.json records
the exact source commit and file hashes used for this snapshot.
