Vim-cellmode
============
This a vim plugin that enables MATLAB-style cell mode execution for python
scripts in vim, assuming an ipython interpreter running in screen (or tmux).

## Demo
[![Youtube demo video](http://img.youtube.com/vi/ju50L7Fcn7w/0.jpg)](http://www.youtube.com/watch?v=ju50L7Fcn7w)

## Usage

Blocks are defined by text markers or vim marks.

For **marker-based blocks**, blocks are delimited by `##`, `#%%` or `# %%` (customizable through
`cellmode_cell_delimiter`).
For example, say you have the following python script :

    ##
    import numpy as np
    print('Hello')                  # (1)
    np.zeros(3)
    ##
    if True:
      print('Yay !')                # (2)
      print('Foo')                  # (3)
    ##

If you put your cursor on the line marked with (1) and hit Ctrl-g, the 3 lines
in the first cell will be sent to tmux. If you hit Ctrl-b, the same will happen
but the cursor will move to the line after the ## (so you can chain Ctrl-b).
The plugin automatically deindent selected lines so that the first line has no
indentation.

**NOTE** that markers at the very 1st and last lines are optional.

For **mark-based blocks**, alphabetic marks defined in a vim buffer using, for
istance `ma` and `mb`, will define a block between the lines with mark `a`
and `b`. (checkout [ShowMarks](https://github.com/vim-scripts/ShowMarks) for
a plugin that visualize the buffer marks.)

You can also visually select line(s) and hit Ctrl-c to send them to tmux.

## Requirements

On Linux, you need `xclip` if you want to use screen.

## Keys mapping

By default, the following mappings are enabled :

* *C-g* sends the current cell to tmux
* *C-b* sends the current cell to tmux, moving to the next one
* *C-c* sends the currently selected lines to tmux
* *C-c C-j* sends the current mark-defined cell to tmux, moving to the next one

You can disable default mappings :

    let g:cellmode_default_mappings='0'

In addition, there is a function to execute all cells above the current line
which isn't bound by default, but you can easily bind it with :

    noremap <silent> <C-a> :call RunTmuxPythonAllCellsAbove()<CR>


## Options

You have to configure the target tmux/screen session/window/pane. By default, the
following is used :

    let g:cellmode_tmux_sessionname=''  " Will try to automatically pickup tmux session
    let g:cellmode_tmux_windowname=''
    let g:cellmode_tmux_panenumber='0'

    let g:cellmode_screen_sessionname='ipython'
    let g:cellmode_screen_window='0'

This scripts relies on temporary files to send text from vim to tmux. To
allow cell execution queuing, we use a rolling buffer of temporary files.
You can control the size of the buffer by defining `g:cellmode_n_files` (10
by default).

To choose between tmux and screen, set `g:cellmode_use_tmux=1` (or 0 if you want screen).
Note that currently, CopyToScreen relies on OSX' pbcopy to set the paste buffer.

You can also configure the cell delimiter. This is done through the
`g:cellmode_cell_delimiter_variable` (prefix it with b: to only
affect the current buffer). This is used inside a regexp so you can use regexp
in it. So for example

    set g:cellmode_cell_delimiter='\(##\|#%%\|#\s%%\)'

will match `##`, `#%%` and `# %%` as cell delimiters. This is the default configuration.


## Use with vanilla python instead of ipython (experimental)

To use with a vanilla python session instead of ipython, set in `.vimrc`

```
let g:cellmode_python_session='python'
```

## Difference with vim-ipython

Note that if you want more advanced integration with IPython (using the new
multi-client architecture), there is the vim-ipython project :
https://github.com/ivanov/vim-ipython/

The main difference with vim-ipython is that this plugin simply emulate a paste
as you would do it manually from vim to ipython. This allow to see the result
of the execution directly in the ipython split whereas vim-ipython uses a
separate vim buffer to show the results.

## License

MIT (see LICENSE)
