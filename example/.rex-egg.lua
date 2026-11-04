return {
  name = "rex-test",
  windows = {
    { name = "code", split = "right", ratio = 40, panes = {
      { cmd = "echo editor pane; exec $SHELL" },
      { split = "below", panes = {
        { cmd = "echo dev pane; exec $SHELL" },
        {},
      }},
    }},
    { name = "agent", cmd = "echo agent window; exec $SHELL" },
  },
}
