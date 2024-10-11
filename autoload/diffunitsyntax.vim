" diffunitsyntax: Highlight word or character based diff units in diff format
"
" Last Change: 2024/10/11
" Version:     1.3
" Author:      Rick Howe (Takumi Ohtani) <rdcxy754@ybb.ne.jp>
" Copyright:   (c) 2024 Rick Howe
" License:     MIT

let s:save_cpo = &cpoptions
set cpo&vim

let s:dus = 'diffunitsyntax'
let s:dbn = []
let s:dhl = {}
let s:dev = ['ColorScheme', 'TextChanged', 'BufDelete']
call execute(['augroup ' . s:dus, 'autocmd!',
              \'autocmd! ColorScheme * call s:HandleEvent(0)', 'augroup END'])

function! s:HandleEvent(en) abort
  let ev = s:dev[a:en]
  if ev == 'ColorScheme'
    let s:dhl = {}
    for bn in s:dbn
      if buflisted(bn)
        call setbufvar(bn, '&syntax', getbufvar(bn, '&syntax'))
      endif
    endfor
  elseif ev == 'TextChanged'
    let &syntax = &syntax
  elseif ev == 'BufDelete'
    call execute('autocmd! ' . s:dus . ' * <buffer=abuf>')
  endif
endfunction

function! diffunitsyntax#DiffUnitSyntax() abort
  if !get(b:, 'DiffUnitSyntax', get(g:, 'DiffUnitSyntax', 1)) | return | endif
  " set events
  let bn = bufnr()
  for en in range(len(s:dev))
    if s:dev[en] != 'ColorScheme'
      call execute('autocmd! ' . s:dus . ' ' . s:dev[en] .
                      \' <buffer=' . bn . '> call s:HandleEvent(' . en . ')')
    endif
  endfor
  if index(s:dbn, bn) == -1 | let s:dbn += [bn] | endif
  " identify a type of diff format
  let fp = #{unified: '^@@ -\d\+\(,\d\+\)\= +\d\+\(,\d\+\)\= @@',
        \context: '^\*\*\* \d\+\(,\d\+\)\= \*\*\*\*',
        \normal: '^\d\+\(,\d\+\)\=[acd]\d\+\(,\d\+\)\=',
        \gitconflict: '^<<<<<<<\(.*\n\)\+=======\(.*\n\)\+>>>>>>>\(.*\n\)\+'}
  for [df, pt] in items(fp) + [['', '']]
    if empty(df) | return | elseif search(pt, 'nw', '', 100) | break | endif
  endfor
  " find a list of corresponding lines to be compared
  let cc = #{1: [], 2: []} | let dd = #{1: [], 2: []}
  if df == 'unified'
    let ln = 1
    while ln <= line('$') + 1
      let tx = getline(ln)
      if tx[0] == '-'
        if tx[:3] == '--- ' && getline(ln + 1)[:3] == '+++ ' | let ln += 1
        else | let dd[1] += [ln]
        endif
      elseif tx[0] == '+' | let dd[2] += [ln]
      else
        if !empty(dd[1]) && !empty(dd[2])
          for ix in [1, 2] | let cc[ix] += [dd[ix]] | endfor
        endif
        let dd = #{1: [], 2: []}
      endif
      let ln += 1
    endwhile
    let sc = 1
  elseif df == 'context'
    let dx = 0
    let ln = 1
    while ln <= line('$') + 1
      let tx = getline(ln)
      if tx[:3] == '*** '
        if getline(ln + 1)[:3] == '--- ' | let ln += 1
        else | let dx = 1
        endif
      elseif tx[:3] == '--- ' | let dx = 2
      elseif 0 < dx
        if tx[0] == '!' | let dd[dx] += [ln]
        else
          for ix in [1, 2]
            if !empty(dd[ix]) | let cc[ix] += [dd[ix]] | endif
          endfor
          let dd = #{1: [], 2: []}
        endif
      endif
      let ln += 1
    endwhile
    let sc = 2
  elseif df == 'normal'
    for ln in range(1, line('$') + 1)
      let tx = getline(ln)
      if tx[0] == '<' | let dd[1] += [ln]
      elseif tx[0] == '>' | let dd[2] += [ln]
      elseif tx[0] != '-'
        if !empty(dd[1]) && !empty(dd[2])
          for ix in [1, 2] | let cc[ix] += [dd[ix]] | endfor
        endif
        let dd = #{1: [], 2: []}
      endif
    endfor
    let sc = 2
  elseif df == 'gitconflict'
    let dx = 0
    for ln in range(1, line('$') + 1)
      let tx = getline(ln)
      if dx == 0 && tx[:6] == '<<<<<<<' | let dx = 1
      elseif dx == 1 && tx[:6] == '=======' | let dx = 2
      elseif dx == 2 && tx[:6] == '>>>>>>>'
        for ix in [1, 2] | let cc[ix] += [dd[ix]] | let dd[ix] = [] | endfor
        let dx = 0
      elseif 0 < dx
        let dd[dx] += [ln]
      endif
    endfor
    let sc = 0
  endif
  let dl = []
  for cx in range(min([len(cc[1]), len(cc[2])]))
    let [d1, d2] = [cc[1][cx], cc[2][cx]]
    for ix in range(min([len(d1), len(d2)]))
      let dl += [[d1[ix], d2[ix]]]
    endfor
  endfor
  " get a diff unit
  let du = get(b:, 'DiffUnit', get(g:, 'DiffUnit', 'Word1'))
  let up = (du == 'Char') ? '\zs' :
            \(du == 'Word2' || du ==# 'WORD') ? '\%(\s\+\|\S\+\)\zs' :
            \(du == 'Word3' || du ==# 'word') ? '\<\|\>' : '\%(\w\+\|\W\)\zs'
  " compare line and find line/column/count for each changed/added unit
  let op = diffutil#DiffOpt()
  let dp = #{}
  for [l1, l2] in dl
    let ll = #{c: [], a: [], d: []}
    let [u1, u2] = [split(getline(l1)[sc:], up), split(getline(l2)[sc:], up)]
    for [i1, n1, i2, n2] in diffutil#DiffFunc(u1, u2, op)
      let hx = (0 < n1 && 0 < n2) ? 'c' : 'a'
      for [ux, lx, ix, nx] in [[u1, l1, i1, n1], [u2, l2, i2, n2]]
        let zl = (0 < ix) ? len(join(ux[: ix - 1], '')) : 0
        if 0 < nx
          let ll[hx] += [[lx, sc + zl, len(join(ux[ix : ix + nx - 1], ''))]]
        else
          let el = (0 < ix) ? len(matchstr(ux[ix - 1], '.$')) : 0
          let sl = (ix < len(ux)) ? len(matchstr(ux[ix], '^.')) : 0
          let ll.d += [[lx, sc + zl - el, el + sl]]
        endif
      endfor
    endfor
    if 0 < sc | let ll.c += [[l1, 0, 1], [l2, 0, 1]] | endif
    for hx in keys(ll)
      if !empty(ll[hx])
        let dp[hx] = (has_key(dp, hx) ? dp[hx] : []) + [ll[hx]]
      endif
    endfor
  endfor
  " get a list of highlights to be used for changed/added units
  if empty(s:dhl)
    let s:dhl = #{c: ['DiffChange'], a: ['DiffAdd'], d: ['DiffDelPos']}
    let bx = map(s:dhl.c + s:dhl.a, 'synIDattr(hlID(v:val), "bg#")')
    let hl = 'diffNormal'
    for fb in ['fg', 'bg']
      for cg in ['cterm', 'gui']
        call execute('highlight ' . hl . ' ' . cg . fb . '=' . fb, 'silent!')
      endfor
      let nn = synIDattr(hlID(hl), fb . '#')
      if !empty(nn) | let bx += [nn] | endif
    endfor
    call execute('highlight clear ' . hl)
    let id = 1
    while 1
      let hl = synIDattr(id, 'name')
      if empty(hl) | break | endif
      if id == synIDtrans(id)
        let bg = synIDattr(id, 'bg#')
        if !empty(bg) && index(bx, bg) == -1 &&
            \empty(filter(['bold', 'underline', 'undercurl', 'strikethrough',
                                \'reverse', 'inverse', 'italic', 'standout'],
                                            \'!empty(synIDattr(id, v:val))'))
          let s:dhl.c += [hl] | let bx += [bg]
        endif
      endif
      let id += 1
    endwhile
    for cg in ['cterm', 'gui']
      call execute('highlight ' . s:dhl.d[0] . ' ' . cg . '=underline',
                                                                  \'silent!')
    endfor
  endif
  " assign highlight to each changed/added unit
  let hp = #{}
  for hx in keys(dp)
    let hn = (0 < get(b:, 'DiffColors', get(g:, 'DiffColors', 1))) ?
                                                          \len(s:dhl[hx]) : 1
    for ix in range(len(dp[hx]))
      let hl = s:dhl[hx][ix % hn]
      let hp[hl] = (has_key(hp, hl) ? hp[hl] : []) + dp[hx][ix]
    endfor
  endfor
  " link highlight and set syntax for each changed/added unit
  let cz = (0 < sc) ? ' contained' : ''
  for [hl, lc] in items(hp)
    if !empty(lc)
      let hz = 'diff' . hl
      call execute('highlight default link ' . hz . ' ' . hl)
      for [l, c, b] in lc
        call execute('syntax match ' . hz . ' /\%' . l . 'l' .
            \'\%>' . c . 'c.\+\%<' . (c + b + 2) . 'c/ containedin=ALL' . cz)
      endfor
    endif
  endfor
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=2 sw=0 sts=-1 et
