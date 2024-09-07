" diffunitsyntax: Highlight word or character based diff units in diff format
"
" Last Change: 2024/09/07
" Version:     1.0
" Author:      Rick Howe (Takumi Ohtani) <rdcxy754@ybb.ne.jp>
" Copyright:   (c) 2024 Rick Howe
" License:     MIT

let s:save_cpo = &cpoptions
set cpo&vim

function! diffunitsyntax#DiffUnitSyntax() abort
  if !get(b:, 'DiffUnitSyntax', get(g:, 'DiffUnitSyntax', 1)) | return | endif
  " identify a type of diff format
  let df = #{unified: '^@@ -\d\+\(,\d\+\)\= +\d\+\(,\d\+\)\= @@',
        \context: '^\*\*\* \d\+\(,\d\+\)\= \*\*\*\*',
        \normal: '^\d\+\(,\d\+\)\=[acd]\d\+\(,\d\+\)\=',
        \gitconflict: '^<<<<<<<\(.*\n\)\+=======\(.*\n\)\+>>>>>>>\(.*\n\)\+'}
  for [ft, pt] in items(df) + [['', '']]
    if empty(ft) | return | elseif search(pt, 'nw', '', 100) | break | endif
  endfor
  " get a diff unit
  let du = get(b:, 'DiffUnit', get(g:, 'DiffUnit', 'Word1'))
  let up = (du == 'Char') ? '\zs' :
            \(du == 'Word2' || du ==# 'WORD') ? '\%(\s\+\|\S\+\)\zs' :
            \(du == 'Word3' || du ==# 'word') ? '\<\|\>' : '\%(\w\+\|\W\)\zs'
  " get a list of highlights for changed and added units
  let [dc, da] = [['DiffChange'], ['DiffAdd']]
  if 0 < get(b:, 'DiffColors', get(g:, 'DiffColors', 1))
    let bx = map(dc + da, 'synIDattr(hlID(v:val), "bg#")')
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
          let dc += [hl] | let bx += [bg]
        endif
      endif
      let id += 1
    endwhile
  endif
  " find a list of corresponding lines to be compared
  let cc = #{1: [], 2: []}
  let dd = #{1: [], 2: []}
  if ft == 'unified'
    for ln in range(1, line('$') + 1)
      let tx = getline(ln)
      if tx[:3] != '--- ' && tx[:3] != '+++ '
        if tx[0] == '-'
          let dd[1] += [ln]
        elseif tx[0] == '+'
          let dd[2] += [ln]
        else
          if !empty(dd[1]) && !empty(dd[2])
            for ix in [1, 2]
              let cc[ix] += [dd[ix]]
            endfor
          endif
          let dd = #{1: [], 2: []}
        endif
      endif
    endfor
    let sc = 1
  elseif ft == 'context'
    let dx = 0
    for ln in range(1, line('$') + 1)
      let tx = getline(ln)
      if tx =~ '^\*\*\* \d'
        let dx = 1
      elseif tx =~ '^--- \d'
        let dx = 2
      elseif 0 < dx
        if tx[0] == '!'
          let dd[dx] += [ln]
        else
          for ix in [1, 2]
            if !empty(dd[ix])
              let cc[ix] += [dd[ix]]
            endif
          endfor
          let dd = #{1: [], 2: []}
        endif
      endif
    endfor
    let sc = 2
  elseif ft == 'normal'
    for ln in range(1, line('$') + 1)
      let tx = getline(ln)
      if tx[0] == '<'
        let dd[1] += [ln]
      elseif tx[0] == '>'
        let dd[2] += [ln]
      elseif tx[0] != '-'
        if !empty(dd[1]) && !empty(dd[2])
          for ix in [1, 2]
            let cc[ix] += [dd[ix]]
          endfor
        endif
        let dd = #{1: [], 2: []}
      endif
    endfor
    let sc = 2
  elseif ft == 'gitconflict'
    let dx = 0
    for ln in range(1, line('$') + 1)
      let tx = getline(ln)
      if dx == 0 && tx =~ '^<<<<<<<'
        let [dx, ig] = [1, 0]
      elseif dx == 1 && tx =~ '^======='
        let [dx, ig] = [2, 0]
      elseif dx == 2 && tx =~ '^>>>>>>>'
        for ix in [1, 2] | let cc[ix] += [dd[ix]] | let dd[ix] = [] | endfor
        let dx = 0
      elseif 0 < dx
        if tx =~ '^|||||||'
          let ig = 1
        elseif ig == 0
          let dd[dx] += [ln]
        endif
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
  " compare line and find line/column/count for each changed/added unit
  let op = s:DiffOpt()
  let ca = #{}
  for lx in range(len(dl))
    let [hc, ha] = [dc[lx % len(dc)], da[lx % len(da)]]
    for hh in [hc, ha]
      if !has_key(ca, hh) | let ca[hh] = [] | endif
    endfor
    let [l1, l2] = dl[lx]
    let [u1, u2] = [split(getline(l1)[sc:], up), split(getline(l2)[sc:], up)]
    for [i1, n1, i2, n2] in s:Diff(u1, u2, op)
      if 0 < n1
        let ca[(0 < n2) ? hc : ha] += [[l1,
                          \sc + ((0 < i1) ? len(join(u1[: i1 - 1], '')) : 0),
                                        \len(join(u1[i1 : i1 + n1 - 1], ''))]]
      endif
      if 0 < n2
        let ca[(0 < n1) ? hc : ha] += [[l2,
                          \sc + ((0 < i2) ? len(join(u2[: i2 - 1], '')) : 0),
                                        \len(join(u2[i2 : i2 + n2 - 1], ''))]]
      endif
    endfor
    if 0 < sc | let ca[hc] += [[l1, 0, 1], [l2, 0, 1]] | endif
  endfor
  " link highlight and set syntax for each changed/added unit
  for [hl, lc] in items(ca)
    if !empty(lc)
      let hz = 'diff' . hl
      call execute('highlight default link ' . hz . ' ' . hl)
      for [l, c, b] in lc
        let ct = 'containedin=ALL'
        if c == 0 && 0 < synID(l, c + 1, 1)
          " add 'contained' if column 1 is syntax highlighted: bug?
          let ct .= ' contained'
        endif
        call execute('syntax match ' . hz . ' /\%' . l . 'l' .
                            \'\%>' . c . 'c.\+\%<' . (c + b + 2) . 'c/ ' . ct)
      endfor
    endif
  endfor
endfunction

function! s:DiffOpt() abort
  let op = #{}
  for [vo, no] in [['icase', 'icase'],
                  \['iblank', 'ignore_blank_lines'],
                  \['iwhite', 'ignore_whitespace'],
                  \['iwhiteall', 'ignore_whitespace_change'],
                  \['iwhiteeol', 'ignore_whitespace_change_at_eol'],
                  \['indent-heuristic', 'indent_heuristic']]
    if &diffopt =~ '\<' . vo . '\>'
      if has('nvim') | let vo = no | endif
      let op[vo] = v:true
    endif
  endfor
  let vo = 'algorithm'
  if &diffopt =~ '\<' . vo . '\>'
    let op[vo] = matchstr(&diffopt, vo . ':\zs\w\+\ze')
  endif
  return op
endfunction

function! s:BuiltinDiff(u1, u2, op) abort
  let [n1, n2] = [len(a:u1), len(a:u2)]
  return (a:u1 ==# a:u2) ? [] : (n1 == 0) ? [[0, 0, 0, n2]] :
                  \(n2 == 0) ? [[0, n1, 0, 0]] : s:DiffFunc(a:u1, a:u2, a:op)
endfunction

if has('nvim')
  function! s:DiffFunc(u1, u2, op) abort
    let op = copy(a:op)
    let [l1, l2] = [join(a:u1, "\n") . "\n", join(a:u2, "\n") . "\n"]
    if has_key(op, 'icase')
      let [l1, l2] = [tolower(l1), tolower(l2)]
      unlet op['icase']
    endif
    let op['result_type'] = 'indices'
    return map(v:lua.vim.diff(l1, l2, op),
                            \'[v:val[0] - ((0 < v:val[1]) ? 1 : 0), v:val[1],
                            \v:val[2] - ((0 < v:val[3]) ? 1 : 0), v:val[3]]')
  endfunction
else
  function! s:DiffFunc(u1, u2, op) abort
    let op = copy(a:op)
    let op['output'] = 'indices'
    return map(diff(a:u1, a:u2, op),
          \'[v:val.from_idx, v:val.from_count, v:val.to_idx, v:val.to_count]')
  endfunction
endif

function! s:PluginDiff(u1, u2, op) abort
  let [u1, u2] = [copy(a:u1), copy(a:u2)]
  for uu in [u1, u2]
    if has_key(a:op, 'icase')
      call map(uu, 'tolower(v:val)')
    endif
    if has_key(a:op, 'iwhiteall')
      call map(uu, 'substitute(v:val, "\\s\\+", "", "g")')
    elseif has_key(a:op, 'iwhite')
      call map(uu, 'substitute(v:val, "\\s\\+", " ", "g")')
      call map(uu, 'substitute(v:val, "\\s\\+$", "", "")')
    elseif has_key(a:op, 'iwhiteeol')
      call map(uu, 'substitute(v:val, "\\s\\+$", "", "")')
    endif
  endfor
  let es = s:TraceDiffChar(u1, u2,
              \has_key(a:op, 'indent-heuristic') && a:op['indent-heuristic'])
  let ic = []
  let [i1, i2] = [0, 0]
  for ed in split(es, '[-+]\+\zs', 1)[: -2]
    let [ce, c1, c2] = map(['=', '-', '+'], 'count(ed, v:val)')
    let [i1, i2] += [ce, ce]
    let ic += [[i1, c1, i2, c2]]
    let [i1, i2] += [c1, c2]
  endfor
  return ic
endfunction

function! s:TraceDiffChar(u1, u2, ih) abort
  " An O(NP) Sequence Comparison Algorithm
  let [u1, u2, eq, e1, e2] = [a:u1, a:u2, '=', '-', '+']
  let [n1, n2] = [len(u1), len(u2)]
  if u1 ==# u2 | return repeat(eq, n1)
  elseif n1 == 0 | return repeat(e2, n2)
  elseif n2 == 0 | return repeat(e1, n1)
  endif
  let [N, M, u1, u2] = (n1 >= n2) ? [n1, n2, u1, u2] : [n2, n1, u2, u1]
  if n1 < n2 | let [e1, e2] = [e2, e1] | endif
  let D = N - M
  let fp = repeat([-1], M + N + 1)
  let etree = []    " [next edit, previous p, previous k]
  let p = -1
  while fp[D] != N
    let p += 1
    let epk = repeat([[]], p * 2 + D + 1)
    for k in range(-p, D - 1, 1) + range(D + p, D, -1)
      let [y, epk[k]] = (fp[k - 1] + 1 > fp[k + 1]) ?
                        \[fp[k - 1] + 1, [e1, [(k > D) ? p - 1 : p, k - 1]]] :
                        \[fp[k + 1], [e2, [(k < D) ? p - 1 : p, k + 1]]]
      let x = y - k
      while x < M && y < N && u2[x] ==# u1[y]
        let epk[k][0] .= eq | let [x, y] += [1, 1]
      endwhile
      let fp[k] = y
    endfor
    let etree += [epk]
  endwhile
  let ses = ''
  while 1
    let ses = etree[p][k][0] . ses
    if [p, k] == [0, 0] | break | endif
    let [p, k] = etree[p][k][1]
  endwhile
  let ses = ses[1 :]
  return a:ih ? s:ReduceDiffHunk(a:u1, a:u2, ses) : ses
endfunction

function! s:ReduceDiffHunk(u1, u2, ses) abort
  " in ==++++/==----, if == units equal to last ++/-- units, swap their SESs
  " (AB vs AxByAB : =+=+++ -> =++++= -> ++++==)
  let [eq, e1, e2] = ['=', '-', '+']
  let [p1, p2] = [-1, -1] | let ses = '' | let ez = ''
  for ed in reverse(split(a:ses, '[+-]\+\zs'))
    let es = ed . ez | let ez = '' | let qe = count(es, eq)
    if 0 < qe
      let [q1, q2] = [count(es, e1), count(es, e2)]
      let [uu, pp, qq] = (qe <= q1 && q2 == 0) ? [a:u1, p1, q1] :
                        \(q1 == 0 && qe <= q2) ? [a:u2, p2, q2] : [[], 0, 0]
      if !empty(uu) && uu[pp - qq - qe + 1 : pp - qq] ==# uu[pp - qe + 1 : pp]
        let ez = es[-qe :] . es[qe : -qe - 1] | let es = es[: qe - 1]
      else
        let [p1, p2] -= [q1, q2]
      endif
    endif
    let [p1, p2] -= [qe, qe]
    let ses = es . ses
  endfor
  let ses = ez . ses
  return ses
endfunction

let s:Diff = function((has('nvim') ? (type(luaeval('vim.diff')) == v:t_func) :
                                \(exists('*diff') && has('patch-9.1.0099'))) ?
                                            \'s:BuiltinDiff' : 's:PluginDiff')

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=2 sw=0 sts=-1 et
