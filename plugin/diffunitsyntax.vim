" diffunitsyntax: Highlight word or character based diff units in diff format
"
" Last Change: 2024/12/01
" Version:     3.0
" Author:      Rick Howe (Takumi Ohtani) <rdcxy754@ybb.ne.jp>
" Copyright:   (c) 2024 Rick Howe
" License:     MIT

if exists('g:loaded_diffunitsyntax') ||
                        \(!has('nvim') ? v:version < 900 : !has('nvim-0.5.0'))
  finish
endif
let g:loaded_diffunitsyntax = 3.0

let s:save_cpo = &cpoptions
set cpo&vim

let s:dus = 'diffunitsyntax'

function! s:CheckSyntax(ev) abort
  let fn = ''
  if a:ev == 0      " Syntax
    "if exists('g:syntax_on')
      let sy = expand('<amatch>')
      if sy == 'diff'                         " diff,gina,gitgutter,signify
        let fn = 'diff'
      elseif sy == 'fugitive' || sy == 'git'  " fugitive
        let fn = 'diff'
      elseif sy == 'gin' || sy =~ '^gin-*'    " gin
        let fn = 'diff'
      elseif sy =~ '^gina-*'                  " gina
        let fn = 'diff'
      elseif sy =~ '^Neogit*'                 " neogit
        let fn = 'neogit'
      endif
    "endif
  elseif a:ev == 1  " CursorHold
    let fn = 'gitsigns'
  endif
  if !empty(fn) | call diffunitsyntax#ApplyDiffUnit(fn) | endif
endfunction

function! s:SetAutocmd() abort
  let ac = [['Syntax *', 0]]
  if has('nvim') && !empty(luaeval('package.loaded["gitsigns"]'))
    let ac += [['CursorHold *', 1]]
  endif
  call execute(['augroup ' . s:dus, 'autocmd!'] + map(ac, '"autocmd " .
                      \v:val[0] . " call s:CheckSyntax(" . v:val[1] . ")"') +
                                                            \['augroup END'])
  for bn in range(1, bufnr('$'))
    call setbufvar(bn, '&syntax', getbufvar(bn, '&syntax'))
  endfor
endfunction

if v:vim_did_enter
  call s:SetAutocmd()
else
  call execute('autocmd VimEnter * ++once call s:SetAutocmd()')
endif

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=2 sw=0 sts=-1 et
