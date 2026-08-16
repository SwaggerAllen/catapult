import Config

# This file stops reading the environment (ORC-4, systems/foundation.md).
# It is the file the substrate's config layer is an argument against: it
# used to fetch three variables and hand-parse one of them, and it
# reported exactly one problem per boot because each way of failing here
# raises — `fetch_env!` on an unset `DATABASE_URL`, `to_integer` on a
# `POOL_SIZE` someone typed wrong. Those three are now foundation's
# `config/0` declarations, loaded once before the root supervisor starts,
# with one report naming every problem at once; the `sslmode` strip and
# the `verify_none` choice became the declared cast on `DATABASE_URL`,
# where they get to fail by name and alongside everything else that is
# wrong.
#
# The file keeps only what `import Config` is for, and today that is
# nothing. It stays rather than being deleted so the next person to
# reach for runtime env reading finds the argument here.
