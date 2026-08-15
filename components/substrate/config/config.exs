import Config

# This package's own dev/test configuration, and nothing a consumer
# inherits: Mix reads only the root project's config, so a dependency's
# `config/` never reaches the tree that depends on it.
#
# It exists for one reason — the export macro's Logger metadata floor
# (`Catapult.Component.API`) sets `component:` and `trace_id:`, and
# Logger drops metadata keys the formatter was never told about. Naming
# them here means the package's own suite exercises the floor as it will
# actually appear, rather than as a keyword list nobody prints. Every
# composing application declares the same keys in its own config, which
# is the split every other value already takes.
config :logger, :default_formatter, metadata: [:component, :trace_id]
