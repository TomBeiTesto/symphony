exclude =
  if :os.type() == {:win32, :nt}, do: [:skip_on_windows], else: []

ExUnit.start(exclude: exclude)

# Define Mox mocks
Mox.defmock(SymphonyElixir.Tracker.MockClient, for: SymphonyElixir.Tracker.Behaviour)
