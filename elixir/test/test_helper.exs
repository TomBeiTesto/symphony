ExUnit.start()

# Define Mox mocks
Mox.defmock(SymphonyElixir.Tracker.MockClient, for: SymphonyElixir.Tracker.Behaviour)
