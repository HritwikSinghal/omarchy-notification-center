-- Config for the hidden test desktop (tests/e2e/nce). Nothing from a real
-- config (binds, autostart, idle, lock) may run inside a test session, so this
-- only fixes the test screen: the headless output nce creates, at scale 1, so
-- every run lays the panel out the same way whatever the real monitors are.
hl.monitor({ output = "E2E", mode = "1920x1080@60", position = "0x0", scale = 1 })
