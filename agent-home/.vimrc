" Use pathogen to put all plugins in .vim/bundle/ in the runtimepath
execute pathogen#infect()

" Standard vim stuff
set nofixendofline
set nocompatible
set encoding=utf-8
syntax on
filetype plugin indent on

" Leader then t launches fuzzy finder (with ag, if present)
" https://github.com/antoine-atmire/dotfiles/blob/master/vimrc#L330
if executable('ag')
    nnoremap <leader>t :call fzf#run({'source':'/usr/local/bin/ag --hidden --ignore .git -g ""', 'sink':'e', 'down': '50%'})<cr>
else
    nnoremap <leader>t :call fzf#run({'source':'find . -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/.idea/*" -not -path "*/target/*" -not -path "*/overlays/*"', 'sink':'e'})<cr>
endif

" Taken from
" https://superuser.com/questions/195022/vim-how-to-synchronize-nerdtree-with-current-opened-tab-file-path
map <leader>f :NERDTreeFind<cr>

" Don't autostart instant markdown preview; launch via \p instead
let g:instant_markdown_autostart = 0
let g:instant_markdown_port = 8888
map <leader>p :InstantMarkdownPreview<cr>

" Git blame shortcut
map <leader>b :Gblame<cr>

" Show tabs more noticeably when in list mode
set listchars=tab:>-

" Use pathogen to put all plugins in .vim/bundle/ in the runtimepath
execute pathogen#infect()

" Standard vim stuff
set nofixendofline
set nocompatible
set encoding=utf-8
syntax on
filetype plugin indent on

" Leader then t launches fuzzy finder (with ag, if present)
" https://github.com/antoine-atmire/dotfiles/blob/master/vimrc#L330
if executable('ag')
    nnoremap <leader>t :call fzf#run({'source':'/usr/local/bin/ag --hidden --ignore .git -g ""', 'sink':'e', 'down': '50%'})<cr>
else
    nnoremap <leader>t :call fzf#run({'source':'find . -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/.idea/*" -not -path "*/target/*" -not -path "*/overlays/*"', 'sink':'e'})<cr>
endif

" Taken from
" https://superuser.com/questions/195022/vim-how-to-synchronize-nerdtree-with-current-opened-tab-file-path
map <leader>f :NERDTreeFind<cr>

" Don't autostart instant markdown preview; launch via \p instead
let g:instant_markdown_autostart = 0
let g:instant_markdown_port = 8888
map <leader>p :InstantMarkdownPreview<cr>

" Git blame shortcut
map <leader>b :Gblame<cr>

" Show tabs more noticeably when in list mode
set listchars=tab:>-

" Insert a randomly generated lowercase uuid at the cursor
map <leader>u :r ! uuid<CR>

au BufRead,BufNewFile *.rbxlx set filetype=xml
au BufRead,BufNewFile *.ts set filetype=typescript
au BufRead,BufNewFile *.sshconfig set filetype=sshconfig
au BufRead,BufNewFile *.zzh set filetype=sshconfig
au BufRead,BufNewFile *.nginx set filetype=nginx
au BufRead,BufNewFile *.turtle set filetype=turtle
au BufRead,BufNewFile *.ttl set filetype=turtle
