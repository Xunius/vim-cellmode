" Implementation of a MATLAB-like cellmode for python scripts where cells
" are delimited by ##
"
" You can define the following globals or buffer config variables
"  let g:cellmode_tmux_sessionname='$ipython'
"  let g:cellmode_tmux_windowname='ipython'
"  let g:cellmode_screen_sessionname='ipython'
"  let g:cellmode_screen_window='0'
"  let g:cellmode_use_tmux=1

"  let g:cellmode_python_session='ipython'

python3 << EOF

import vim

# The set of marks that will be used as cell delimiters.
DEFAULT_VALID_MARKS = 'abcdefghijklmnopqrstuvqxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'

def get_cell_by_marks():
    # Find a cell by vim marks
	# The beginning and end of file are assumed to be marked

    cur_row = int(vim.current.window.cursor[0])
    # get a list of all of the mark locations
    locations = []
    for letter in DEFAULT_VALID_MARKS:
        location_of_mark = vim.current.buffer.mark(letter)
        if location_of_mark is not None:
            locations.append(location_of_mark[0])
    # If no marks found, return 0s
    if len(locations) == 0:
        return 0, 0, 0
	# make dummy "marks" at the beginning of the file
    locations = sorted(set([1] + locations))

	# find which cell we are in. The line that the cursor is on should always be included in the cell.
    cell_start = [mark for mark in locations if mark <= cur_row][-1]
    next_cell_start = [mark for mark in locations if mark > cur_row]

    # if there are no marks after the current row, then select to the end of the buffer
    cell_end = next_cell_start[0]-1 if next_cell_start else len(vim.current.buffer)

    # if there are marks after this one, make them the start of the next cell, otherwise, stay where you are
    next_cell_start = next_cell_start[0] if next_cell_start else cur_row

    return cell_start, cell_end, next_cell_start

EOF

function! PythonRemoveBlankLine(lines)
  " Remove empty lines from list of strings
  let l:lines2 = filter(a:lines, 'len(v:val)')
  call filter(l:lines2, 'match(v:val, ' . "'\v^\s*$')")
  return l:lines2
endfunction

function! PythonUnindent(code)
  " The code is unindented so the first selected line has 0 indentation
  " So you can select a statement from inside a function and it will run
  " without python complaining about indentation.
  let l:lines = split(a:code, "\n")
  let l:lines = PythonRemoveBlankLine(l:lines)
  if len(l:lines) == 0 " Special case for empty string
    return a:code
  end
  let l:nindents = strlen(matchstr(l:lines[0], '^\s*'))
  " Remove nindents from each line
  let l:subcmd = 'substitute(v:val, "^\\s\\{' . l:nindents . '\\}", "", "")'
  call map(l:lines, l:subcmd)
  let l:ucode = join(l:lines, "\n")
  return l:ucode
endfunction

function! GetVar(name, default)
  " Return a value for the given variable, looking first into buffer, then
  " globals and defaulting to default
  if (exists ("b:" . a:name))
    return b:{a:name}
  elseif (exists ("g:" . a:name))
    return g:{a:name}
  else
    return a:default
  end
endfunction

function! CleanupTempFiles()
  " Called when leaving current buffer; Cleans up temporary files
  if (exists('b:cellmode_fnames'))
    for fname in b:cellmode_fnames
      call delete(fname)
    endfor
    unlet b:cellmode_fnames
  end
endfunction

function! GetNextTempFile()
  " Returns the next temporary filename to use
  "
  " We use temporary files to communicate with tmux. That is we :
  " - write the content of a register to a tmpfile
  " - have ipython running inside tmux load and run the tmpfile
  " If we use only one temporary file, quick execution of multiple cells will
  " result in the tmpfile being overrident. So we use multiple tmpfile that
  " act as a rolling buffer (the size of which is configured by
  " cellmode_n_files)
  if !exists("b:cellmode_fnames")
    au BufDelete <buffer> call CleanupTempFiles()
    let b:cellmode_fnames = []
    for i in range(1, b:cellmode_n_files)
      call add(b:cellmode_fnames, tempname() . ".ipy")
    endfor
    let b:cellmode_fnames_index = 0
  end
  let l:cellmode_fname = b:cellmode_fnames[b:cellmode_fnames_index]
  " TODO: Would be better to use modulo, but vim doesn't seem to like % here...
  if (b:cellmode_fnames_index >= b:cellmode_n_files - 1)
    let b:cellmode_fnames_index = 0
  else
    let b:cellmode_fnames_index += 1
  endif

  "echo 'cellmode_fname : ' . l:cellmode_fname
  return l:cellmode_fname
endfunction

function! DefaultVars()
  " Load and set defaults config variables :
  " - b:cellmode_fname temporary filename
  " - g:cellmode_tmux_sessionname, g:cellmode_tmux_windowname,
  "   g:cellmode_tmux_panenumber : default tmux
  "   target
  " - b:cellmode_tmux_sessionname, b:cellmode_tmux_windowname,
  "   b:cellmode_tmux_panenumber :
  "   buffer-specific target (defaults to g:)
  let b:cellmode_n_files = GetVar('cellmode_n_files', 10)

  if !exists("b:cellmode_use_tmux")
    let b:cellmode_use_tmux = GetVar('cellmode_use_tmux', 1)
  end

  if !exists("b:cellmode_cell_delimiter")
    " By default, use ##, #%% or # %% (to be compatible with spyder)
    let b:cellmode_cell_delimiter = GetVar('cellmode_cell_delimiter',
                                         \ '\(##\|#%%\|#\s%%\)')
  end

  if !exists("b:cellmode_tmux_sessionname") ||
   \ !exists("b:cellmode_tmux_windowname")
   "\ !exists("b:cellmode_tmux_panenumber")
    " Empty target session and window by default => try to automatically pick
    " tmux session
    let b:cellmode_tmux_sessionname = GetVar('cellmode_tmux_sessionname', '')
    let b:cellmode_tmux_windowname = GetVar('cellmode_tmux_windowname', '')
    "let b:cellmode_tmux_panenumber = GetVar('cellmode_tmux_panenumber', '2')
  end

  if !exists("g:cellmode_screen_sessionname") ||
   \ !exists("b:cellmode_screen_window")
    let b:cellmode_screen_sessionname = GetVar('cellmode_screen_sessionname', 'ipython')
    let b:cellmode_screen_window = GetVar('cellmode_screen_window', '0')
  end
endfunction

function! CallSystem(cmd)
  " Execute the given system command, reporting errors if any
  let l:out = system(a:cmd)
  if v:shell_error != 0
    echom 'Vim-cellmode, error running ' . a:cmd . ' : ' . l:out
  end
endfunction

function! PickTmuxPane()
	" choose the current tmux pane to send code to"

	" get a list of pane numbers
	let l:panes = systemlist("tmux list-panes | awk -F: '{print$1}'")
	" If no panes in current window, return -1, which will trigger an abort later
	if len(l:panes) == 0
		return '-1'
	endif

	" find the current pane, need to strip trailing whitespaces
	let l:current_pane = system("tmux display -p '#{pane_index}' | tr '\n' ' '")
	let l:current_pane = substitute(l:current_pane, '^\s*\(.\{-}\)\s*$', '\1', '')

	" if only two panes, choose the one other than the vim pane
	if len(l:panes) == 2
		for i in l:panes
			if i != l:current_pane
				return i
			endif
		endfor
	" if more than 2, prompt for user choice
	else
		" let tmux display pane numbers
		call system("tmux display-panes")
	    let l:sel_pane = input("Select pane. [1-9] ", '2')
		if index(l:panes, l:sel_pane) == -1
			echom("Invalid pane number")
			return '-1'
		elseif l:sel_pane == l:current_pane
			echom("Selected current pane")
			return '-1'
		else
			return l:sel_pane
		endif
	endif
endfunction


function! CopyToTmux(code)
  " Copy the given code to tmux. We use a temp file for that
  let l:lines = split(a:code, "\n")
  " If the file is empty, it seems like tmux load-buffer keep the current
  " buffer and this cause the last command to be repeated. We do not want that
  " to happen, so add a dummy string
  if len(l:lines) == 0
    call add(l:lines, ' ')
  end
  let l:cellmode_fname = GetNextTempFile()
  call writefile(l:lines, l:cellmode_fname)

  " tmux requires the sessionname to start with $ (for example $ipython to
  " target the session named 'ipython'). Except in the case where we
  " want to target the current tmux session (with vim running in tmux)
  if strlen(b:cellmode_tmux_sessionname) == 0
    let l:sprefix = ''
  else
    let l:sprefix = '$'
  end

  let target_pane = PickTmuxPane()
  if target_pane == '-1'
	  return
  endif
  let target = l:sprefix . b:cellmode_tmux_sessionname . ':'
             \ . b:cellmode_tmux_windowname . '.'
             \ . target_pane
             "\ . b:cellmode_tmux_panenumber

  let l:py_session = GetVar('cellmode_python_session', 'ipython')
  if l:py_session == 'python'
	  call CallSystem('tmux load-buffer ' . l:cellmode_fname)
	  call CallSystem('tmux paste-buffer -t ' . target)
  else
	  " Ipython has some trouble if we paste large buffer if it has been started
	  " in a small console. We use %load to work around that
	  call CallSystem("tmux set-buffer \"%load -y " . l:cellmode_fname . "\n\"")
	  call CallSystem('tmux paste-buffer -t "' . target . '"')
	  " In ipython5, the cursor starts at the top of the lines, so we have to move
	  " to the bottom
	  let downlist = repeat('Down ', len(l:lines) + 1)
	  call CallSystem('tmux send-keys -t "' . target . '" ' . downlist)
  endif

  " Simulate double enter to run loaded code
  call CallSystem('tmux send-keys -t "' . target . '" Enter Enter')
endfunction

function! CopyToScreen(code)
  let l:lines = split(a:code, "\n")
  " If the file is empty, it seems like tmux load-buffer keep the current
  " buffer and this cause the last command to be repeated. We do not want that
  " to happen, so add a dummy string
  if len(l:lines) == 0
    call add(l:lines, ' ')
  end
  let l:cellmode_fname = GetNextTempFile()
  call writefile(l:lines, l:cellmode_fname)

  if has('macunix')
    call system("pbcopy < " . l:cellmode_fname)
  else
    call system("xclip -i -selection c " . l:cellmode_fname)
  end
  call system("screen -S " . b:cellmode_screen_sessionname .
             \ " -p " . b:cellmode_screen_window
              \ . " -X stuff '%paste\n'")
endfunction

function! RunTmuxPythonReg()
  " Paste into tmux the content of the register @a
  let l:code = PythonUnindent(@a)
  if b:cellmode_use_tmux
    call CopyToTmux(l:code)
  else
    call CopyToScreen(l:code)
  end
endfunction

function! RunTmuxPythonCellByMarks(restore_cursor)
  " Run a cell of python code defined by buffer marks

  call DefaultVars()
  if a:restore_cursor
    let l:winview = winsaveview()
  end

  " find the cell by marks
  let l:cell_lines = py3eval('get_cell_by_marks()')
  let l:cell_start = l:cell_lines[0]
  let l:cell_end = l:cell_lines[1]
  " if both start and end are 0, no mark in buffer
  if l:cell_start == 0 && l:cell_end == 0
	  if input("No marks defined. Execute entire script ? y|[n] ", 'n') != "y"
	    return
      else
	    let l:cell_start = '1'
		let l:cell_end = '$'
	  endif
  endif

  " yank range
  let l:pat = ':' . l:cell_start . ',' . l:cell_end . 'y a'
  silent exe l:pat

  " Now, we want to position ourselves inside the next block to allow block
  " execution chaining (of course if restore_cursor is true, this is a no-op
  " Move to the last character of the previously yanked text
  execute "normal! ']"
  " Move 2 line down
  execute "normal! 2j"

  call RunTmuxPythonReg()
  if a:restore_cursor
    call winrestview(l:winview)
  end


endfunction

function! RunTmuxPythonCell(restore_cursor)
  " This is to emulate MATLAB's cell mode
  "
  " Old way of cell finding --- {{{
  " Cells are delimited by ##. Note that there should be a ## at the end of the
  " file
  " The :?##?;/##/ part creates a range with the following
  " ?##? search backwards for ##

  " Then ';' starts the range from the result of the previous search (##)
  " /##/ End the range at the next ##
  " See the doce on 'ex ranges' here :
  " http://tnerual.eriogerg.free.fr/vimqrc.html
  " Old way of cell finding --- }}}
  "
  " New way of cell finding --- {{{
  " Search backward for the cell delimiters, if found, move one line down
  " to skip the ## line itself. If not found, assuming the beginging of the
  " file (line 1).
  " Search forward for the cell delimiters, if found, move one line up
  " to skip the ## line itself. If not found, assuming the end of the
  " file (line $).
  " Then yank the range :cell_start,cell_end y a
  " New way of cell finding --- }}}
  "
  " Note that cell delimiters can be configured through
  " b:cellmode_cell_delimiter, but we keep ## in the comments for simplicity
  call DefaultVars()
  if a:restore_cursor
    let l:winview = winsaveview()
  end

  " Find cell end line number
  let l:cell_end = search(b:cellmode_cell_delimiter, 'W')
  if l:cell_end == 0
	  " if not found, assuming end of file
	  let l:cell_end = '$'
  else
	  " if found, move one line up
	  let l:cell_end -= 1
  endif
  " Find cell start line number
  let l:cell_start = search(b:cellmode_cell_delimiter, 'bW')
  if l:cell_start == 0
	  " if not found, assuming beginning of file
	  let l:cell_start = '1'
  else
	  " if found, move one line down
	  let l:cell_start += 1
  endif

  " If the entire file is found, prompt for confirmation
  if l:cell_start=='1' && l:cell_end=='$'
	  if input("No cell defined. Execute entire script ? [y]|n ", 'y') != "y"
	    return
	  endif
  endif
  " yank range
  let l:pat = ':' . l:cell_start . ',' . l:cell_end . 'y a'
  silent exe l:pat

  " Now, we want to position ourselves inside the next block to allow block
  " execution chaining (of course if restore_cursor is true, this is a no-op
  " Move to the last character of the previously yanked text
  execute "normal! ']"
  " Move 2 line down
  execute "normal! 2j"

  call RunTmuxPythonReg()
  if a:restore_cursor
    call winrestview(l:winview)
  end
endfunction

function! RunTmuxPythonAllCellsAbove()
  " Executes all the cells above the current line. That is, everything from
  " the beginning of the file to the closest ## above the current line
  call DefaultVars()

  " Ask the user for confirmation, this could lead to huge execution
  if input("Execute all cells above ? [y]|n ", 'y') != "y"
    return
  endif

  let l:cursor_pos = getpos(".")

  " Creates a range from the first line to the closest ## above the current
  " line (?##? searches backward for ##)
  let l:end_line = search(b:cellmode_cell_delimiter, 'bW')
	if l:end_line > 1
		" if found, move 1 line up from ##
		let l:end_line -= 1
	else
	  " if not found, quit
		redraw
		echom "No cells found above current line"
		return
	endif

	let l:pat = ':1,' . l:end_line . 'y a'
	silent exe l:pat

  call RunTmuxPythonReg()
  call setpos(".", l:cursor_pos)
endfunction

function! RunTmuxPythonChunk() range
  call DefaultVars()
  " Yank current selection to register a
  silent normal gv"ay
  call RunTmuxPythonReg()
endfunction

function! RunTmuxPythonLine()
  call DefaultVars()
  " Yank current selection to register a
  silent normal "ayy
  call RunTmuxPythonReg()
endfunction

" Returns:
"   1 if the var is set, 0 otherwise
function! InitVariable(var, value)
    if !exists(a:var)
        execute 'let ' . a:var . ' = ' . "'" . a:value . "'"
        return 1
    endif
    return 0
endfunction

call InitVariable("g:cellmode_default_mappings", 1)

if g:cellmode_default_mappings
    vmap <silent> <C-c> :call RunTmuxPythonChunk()<CR>
    noremap <silent> <C-b> :call RunTmuxPythonCell(0)<CR>
    noremap <silent> <C-g> :call RunTmuxPythonCell(1)<CR>
    noremap <silent> <C-c><C-j> :call RunTmuxPythonCellByMarks(1)<CR>
endif
