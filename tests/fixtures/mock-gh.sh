#!/usr/bin/env bash
# Synthetic visibility service for guard tests; no network or authentication.
case "${3:-}" in example/private) printf 'true\n' ;; *) printf 'false\n' ;; esac
