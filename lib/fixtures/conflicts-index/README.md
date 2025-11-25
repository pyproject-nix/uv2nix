# conflicts-index

Test fixture for conflicts with resolution markers containing synthetic conflict extras.

This reproduces the issue where selecting a conflict group causes packages to be incorrectly
filtered out because the synthetic conflict extras (e.g., `extra == 'group-10-conflicts-index-group-a'`)
are not included in the environment when evaluating resolution markers.
