# Preparing a publication snapshot

The private development and preparation repositories keep their original histories.
Their workflow-generated merge metadata is not the publication source. Do not expose that
history by changing a private workbench's visibility.

From a clean, committed candidate checkout, with Node 18+ and Git installed:

```sh
node tests/prepare-snapshot.mjs "<new-directory-outside-the-repository>"
```

The command produces a versioned .bundle and snapshot.json. It creates one parentless
commit with a generic subject, neutral release-preparation identity and UTC timestamp.
MIT author credits remain in the original file tree. The temporary object store is kept
outside the deliverable directory and removed after verification. The source's refs and
history are not rewritten, pushed or changed.

The tool imports its own bundle into a separate bare repository, verifies exactly one
commit and one main ref, checks the exact source tree hash, runs git fsck, and scans the
imported tree plus commit message. Existing output directories and dirty sources are
refused. A completed artifact needs snapshot.json and a successful exit; a partial output
directory after a failure is not an approved artifact.

## Owner verification

Check the bundle SHA-256 against bundleSha256 in snapshot.json, then import it locally:

```sh
git clone --branch main "<bundle-file>" "<new-local-folder>"
git -C "<new-local-folder>" rev-list --all --count
git -C "<new-local-folder>" rev-parse HEAD^{tree}
```

The count must be 1; the tree must match the manifest. From that folder run:

```sh
node tests/release-scan.mjs --history
node tests/release-scan.mjs --history --redaction-list "<private-list-path>"
```

The owner alone supplies the private list. The agent's pattern scan cannot clear that gate.
Run the independent setup/task and guard review described in INDEPENDENT-TEST.md against
these exact bytes. A later source change requires a new bundle and verification record.

Importing locally is preparation only. Creating or changing a public remote, uploading the
bundle, making a repo public, submitting a directory entry and announcements each wait for
the owner's explicit go-ahead. No publication step is part of this tool.

Before remote publication, confirm the README/manifest repository URLs match the chosen
destination. Renaming or replacing an existing hosted repo is a separate owner action.
A URL edit changes the tree and requires a regenerated bundle and affected checks.
