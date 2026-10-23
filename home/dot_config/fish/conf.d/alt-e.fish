# fish 4 reads both ESC e and the CSI u encoding of Alt+E as alt-e. This shadows the preset alt-e
# (edit_command_buffer); alt-v still opens the editor.
bind alt-e _dots_ai_cmd
