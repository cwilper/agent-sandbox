" Use auto-indent and four-space tabs by default
set autoindent
set tabstop=4
set shiftwidth=4
set expandtab

" Use brighter colors
" (tip: update your terminal program's prefs to make blue brighter!)
set background=dark

" Highlight the line the cursor is on
set cursorline
highlight CursorLine cterm=NONE ctermbg=darkblue

" Put a line at column 120
set colorcolumn=120
highlight ColorColumn ctermbg=darkgray
" Highlight trailing whitespace in red
highlight ExtraWhitespace ctermbg=red guibg=red
match ExtraWhitespace /\s\+$/
autocmd BufWinEnter * match ExtraWhitespace /\s\+$/
autocmd InsertEnter * match ExtraWhitespace /\s\+\%#\@<!$/
autocmd InsertLeave * match ExtraWhitespace /\s\+$/
autocmd BufWinLeave * call clearmatches()

" Use tt to open NERDTree and browse files
map tt :NERDTree<CR>

map <c-y> ]m
map <c-t> [m

" Open epub files as zips
au BufReadCmd   *.epub      call zip#Browse(expand("<amatch>"))

" Use Ctrl-hjkl to navigate between windows
map <C-H> <C-W>h
map <C-J> <C-W>j
map <C-K> <C-W>k
map <C-L> <C-W>l

" Use Ctrl-uiop to adjust window borders
map <C-U> :res -1<CR>
map <C-I> :vertical res -1<CR>
map <C-O> :vertical res +1<CR>
map <C-P> :res +1<CR>

" Use <C-W>rtw to remove all trailing whitespace
nnoremap <C-W>rtw :%s/\s\+$//e<CR>
