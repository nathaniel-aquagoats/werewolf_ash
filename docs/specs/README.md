# Specs

Each file here is an approved spec: the contract one bead is built and
reviewed against.

- **Approve** a spec by merging its pull request, titled
  `spec(<bead-id>): …`. Merging accepts every recommendation in the spec's
  **For the owner** card. To ask for a change instead, comment on the pull
  request.
- **The queue** builds up to two beads at once, in the order specs were
  merged, once every bead on a spec's `Depends on:` line is implemented. Two
  beads run together only when their Touches sections share no source file.
  Nothing new starts while any pull request is labelled `needs-human`.
- **Implemented** specs stay here, stamped `Implemented in PR #N.` under
  the title.
- A merged spec changes only through another spec pull request.
