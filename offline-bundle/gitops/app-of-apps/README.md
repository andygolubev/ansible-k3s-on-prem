# Offline App Of Apps

This folder is the source for the Argo CD app-of-apps repository that is mirrored into the isolated cluster during offline bootstrap.

The bootstrap playbook creates a local Git mirror from this folder and applies `root.yaml`. The root Application reads child Application manifests from `applications/`.

