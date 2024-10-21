" diffunitsyntax: Highlight word or character based diff units in diff format
"
" Last Change: 2024/10/21
" Version:     2.0
" Author:      Rick Howe (Takumi Ohtani) <rdcxy754@ybb.ne.jp>
" Copyright:   (c) 2024 Rick Howe
" License:     MIT

let s:save_cpo = &cpoptions
set cpo&vim

let s:dus = 'diffunitsyntax'

function! diffunitsyntax#DiffUnitSyntax() abort
  if !get(b:, 'DiffUnitSyntax', get(g:, 'DiffUnitSyntax', 1)) | return | endif
  let dp = s:FindDiffUnitPos()
  if !empty(dp)
    if empty(s:dhl) | let s:dhl = s:SetDiffHighlight() | endif
    let hp = #{}
    for hx in keys(s:dhl)
      let hn = (0 < get(b:, 'DiffColors', get(g:, 'DiffColors', 1))) ?
                                                          \len(s:dhl[hx]) : 1
      if has_key(dp, hx)
        for ix in range(len(dp[hx]))
          let hl = s:dhl[hx][ix % hn]
          let hp[hl] = (has_key(hp, hl) ? hp[hl] : []) + dp[hx][ix]
        endfor
      endif
    endfor
    call s:ShowDiffUnit(hp)
  endif
  call s:SetEvent()
endfunction

function! s:FindDiffUnitPos() abort
  " use the saved position if nothing has changed
  let du = get(b:, 'DiffUnit', get(g:, 'DiffUnit', 'Word1'))
  let dp = getbufvar(bufnr(), s:dus)
  if empty(dp) || dp.u != du
    " identify diff format
    let ok = 0
    for [df, pt] in [['unified', '^@@ -\d\+\(,\d\+\)\= +\d\+\(,\d\+\)\= @@'],
          \['context', '^\*\*\* \d\+\(,\d\+\)\= \*\*\*\*'],
          \['normal', '^\d\+\(,\d\+\)\=[acd]\d\+\(,\d\+\)\='],
          \['gitconflict', '^<\{7}\(.*\n\)\+=\{7}\(.*\n\)\+>\{7}\(.*\n\)\+'],
          \['diffindicator', '^[-+<>]']]
      if 0 < search(pt, 'nw', '', 100) | let ok = 1 | break | endif
    endfor
    let dp = {}
    if ok
      let dp = #{u: du}
      " find a list of corresponding lines to be compared
      let [cl, oc] = call('s:' . df, [])
      " set a pair of diff line
      let dl = []
      for cx in range(min([len(cl[1]), len(cl[2])]))
        let [c1, c2] = [cl[1][cx], cl[2][cx]]
        for ix in range(min([len(c1), len(c2)]))
          let dl += [[c1[ix], c2[ix]]]
        endfor
      endfor
      " get a type of diff unit
      let up = (du == 'Char') ? '\zs' :
            \(du == 'Word2' || du ==# 'WORD') ? '\%(\s\+\|\S\+\)\zs' :
            \(du == 'Word3' || du ==# 'word') ? '\<\|\>' : '\%(\w\+\|\W\)\zs'
      " compare line and find line/column/count for each unit
      let op = diffutil#DiffOpt()
      for [l1, l2] in dl
        let pv = #{c: [], a: [], d: []}
        let [u1, u2] =
                  \[split(getline(l1)[oc:], up), split(getline(l2)[oc:], up)]
        for [i1, n1, i2, n2] in diffutil#DiffFunc(u1, u2, op)
          let hx = (0 < n1 && 0 < n2) ? 'c' : 'a'
          for [ux, lx, ix, nx] in [[u1, l1, i1, n1], [u2, l2, i2, n2]]
            let zl = (0 < ix) ? len(join(ux[: ix - 1], '')) : 0
            if 0 < nx
              let pv[hx] += [[lx, oc + zl + 1,
                                        \len(join(ux[ix : ix + nx - 1], ''))]]
            else
              let el = (0 < ix) ? len(matchstr(ux[ix - 1], '.$')) : 0
              let sl = (ix < len(ux)) ? len(matchstr(ux[ix], '^.')) : 0
              let pv.d += [[lx, oc + zl - el + 1, el + sl]]
            endif
          endfor
        endfor
        if 0 < oc | let pv.c += [[l1, 1, 1], [l2, 1, 1]] | endif
        for hx in keys(pv)
          if !empty(pv[hx])
            let dp[hx] = (has_key(dp, hx) ? dp[hx] : []) + [pv[hx]]
          endif
        endfor
      endfor
    endif
    call setbufvar(bufnr(), s:dus, dp)
  endif
  return dp
endfunction

function! s:unified() abort
  let cl = #{1: [], 2: []} | let dl = #{1: [], 2: []}
  let ln = 1
  while ln <= line('$') + 1
    let tx = getline(ln)
    if tx[0] == '-'
      if tx[:3] == '--- ' && getline(ln + 1)[:3] == '+++ ' | let ln += 1
      else | let dl[1] += [ln]
      endif
    elseif tx[0] == '+' | let dl[2] += [ln]
    else
      if !empty(dl[1]) && !empty(dl[2])
        for ix in [1, 2] | let cl[ix] += [dl[ix]] | endfor
      endif
      let dl = #{1: [], 2: []}
    endif
    let ln += 1
  endwhile
  return [cl, 1]
endfunction

function! s:context() abort
  let cl = #{1: [], 2: []} | let dl = #{1: [], 2: []}
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
      if tx[0] == '!' | let dl[dx] += [ln]
      else
        for ix in [1, 2]
          if !empty(dl[ix]) | let cl[ix] += [dl[ix]] | endif
        endfor
        let dl = #{1: [], 2: []}
      endif
    endif
    let ln += 1
  endwhile
  return [cl, 2]
endfunction

function! s:normal() abort
  let cl = #{1: [], 2: []} | let dl = #{1: [], 2: []}
  for ln in range(1, line('$') + 1)
    let tx = getline(ln)
    if tx[0] == '<' | let dl[1] += [ln]
    elseif tx[0] == '>' | let dl[2] += [ln]
    elseif tx[0] != '-'
      if !empty(dl[1]) && !empty(dl[2])
        for ix in [1, 2] | let cl[ix] += [dl[ix]] | endfor
      endif
      let dl = #{1: [], 2: []}
    endif
  endfor
  return [cl, 2]
endfunction

function! s:gitconflict() abort
  let cl = #{1: [], 2: []} | let dl = #{1: [], 2: []}
  let dx = 0
  for ln in range(1, line('$') + 1)
    let tx = getline(ln)
    if dx == 0 && tx[:6] == '<<<<<<<' | let dx = 1
    elseif dx == 1 && tx[:6] == '=======' | let dx = 2
    elseif dx == 2 && tx[:6] == '>>>>>>>'
      for ix in [1, 2] | let cl[ix] += [dl[ix]] | let dl[ix] = [] | endfor
      let dx = 0
    elseif 0 < dx
      let dl[dx] += [ln]
    endif
  endfor
  return [cl, 0]
endfunction

function! s:diffindicator() abort
  let cl = #{1: [], 2: []} | let dl = #{1: [], 2: []}
  for ln in range(1, line('$') + 1)
    let tx = getline(ln)
    if tx[0] == '-' || tx[0] == '<' | let dl[1] += [ln]
    elseif tx[0] == '+' || tx[0] == '>' | let dl[2] += [ln]
    else
      if !empty(dl[1]) && !empty(dl[2])
        for ix in [1, 2] | let cl[ix] += [dl[ix]] | endfor
      endif
      let dl = #{1: [], 2: []}
    endif
  endfor
  return [cl, 1]
endfunction

let s:dhl = {}

function! s:SetDiffHighlight() abort
  " set a list of highlights for diff units
  let dh = #{c: ['DiffChange'], a: ['DiffAdd'], d: ['DiffDelPos']}
  let bx = map(dh.c + dh.a, 'synIDattr(hlID(v:val), "bg#")')
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
        let dh.c += [hl] | let bx += [bg]
      endif
    endif
    let id += 1
  endwhile
  for cg in ['cterm', 'gui']
    call execute('highlight ' . dh.d[0] . ' ' . cg . '=underline', 'silent!')
  endfor
  return dh
endfunction

function! s:ShowDiffUnit(hp) abort
  " link highlight and set syntax for each unit
  let cz = {}
  for [hl, lc] in items(a:hp)
    if !empty(lc)
      let hz = 'diff' . hl
      call execute('highlight default link ' . hz . ' ' . hl)
      for [l, c, b] in lc
        if !has_key(cz, l) | let cz[l] = empty(synstack(l, c)) | endif
        call execute('syntax match ' . hz . ' /\%' . l . 'l\%>' . (c - 1) .
                            \'c.\+\%<' . (c + b + 1) . 'c/ containedin=ALL' .
                                                \(cz[l] ? '' : ' contained'))
      endfor
    endif
  endfor
endfunction

let s:dev = ['ColorScheme', 'OptionSet', 'TextChanged', 'BufDelete']

function! s:SetEvent() abort
  call execute(['augroup ' . s:dus, 'autocmd!'])
  let bz = filter(range(1, bufnr('$')),
            \'bufloaded(v:val) && type(getbufvar(v:val, s:dus)) == type({})')
  if !empty(bz)
    let ac = []
    for en in range(len(s:dev))
      if s:dev[en] == 'ColorScheme' | let ac += [[en, '*']]
      elseif s:dev[en] == 'OptionSet' | let ac += [[en, 'diffopt']]
      else | for bn in bz | let ac += [[en, '<buffer=' . bn . '>']] | endfor
      endif
    endfor
    call execute(map(ac, '"autocmd! " . s:dev[v:val[0]] . " " . v:val[1] .
                                  \" call s:HandleEvent(" . v:val[0] . ")"'))
  endif
  call execute('augroup END')
  if empty(bz) | call execute('augroup! ' . s:dus) | endif
endfunction

function! s:HandleEvent(en) abort
  let Don = {bn -> bufloaded(bn) && type(getbufvar(bn, s:dus)) == type({})}
  let Dcl = {bn -> setbufvar(bn, s:dus, {})}
  let Syn = {bn -> setbufvar(bn, '&syntax', getbufvar(bn, '&syntax'))}
  let ev = s:dev[a:en]
  if ev == 'ColorScheme'
    let s:dhl = {}
    for bn in range(1, bufnr('$'))
      if Don(bn) | call Syn(bn) | endif
    endfor
  elseif ev == 'OptionSet'
    if v:option_old != v:option_new
      for bn in range(1, bufnr('$'))
        if Don(bn) | call Dcl(bn) | call Syn(bn) | endif
      endfor
    endif
  elseif ev == 'TextChanged'
    let bn = str2nr(expand('<abuf>'))
    call Dcl(bn) | call Syn(bn)
  elseif ev == 'BufDelete'
    let bv = getbufvar(str2nr(expand('<abuf>')) , '')
    if has_key(bv, s:dus) | unlet bv[s:dus] | endif
    call s:SetEvent()
  endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=2 sw=0 sts=-1 et
