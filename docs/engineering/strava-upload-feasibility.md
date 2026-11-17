# Strava upload feasibility

Verified 17 November 2026 against official documentation:

- https://developers.strava.com/docs/uploads/
- https://developers.strava.com/docs/authentication/

Strava supports FIT, TCX and GPX uploads. Uploads require the athlete's `activity:write` grant, enqueue asynchronous processing and can fail for malformed or duplicate data. A submitted request is not a confirmed published activity; any future uploader must track processing status and preserve the local original on failure. Existing STRAP measured-route GPX/FIT exports are independently validated and can be shared without implementing an account connection.

The documented authorization-code/token flow requires an application client ID and secret from registration. STRAP needs its own registered application, authorized redirect configuration and explicit athlete grant. No borrowed client, embedded client secret, scraped session or third-party token is an acceptable substitute. A token exchange service with protected credentials and per-athlete token handling must be designed before in-app connection/upload is enabled. No credentials or registration are present in this worktree.

H9 feasibility research is implemented. H10 in-app integration remains BLOCKED by STRAP-owned registration, secure exchange deployment and athlete authorization. GPX/FIT export does not prove Strava cloud acceptance; no upload has been attempted and no activity was published.
