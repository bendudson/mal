/* Save command-line arguments from the top-level program before entering a procedure */
command_line_args. = ""
command_line_args.0 = arg()
do i=1 to command_line_args.0
  command_line_args.i = arg(i)
end

call main
exit

#include "readline.rexx"
#include "reader.rexx"
#include "printer.rexx"
#include "types.rexx"
#include "env.rexx"
#include "core.rexx"

read: procedure expose values. err /* read(str) */
  return read_str(arg(1))

pair?: procedure expose values. /* pair?(ast) */
  ast = arg(1)
  return sequential?(ast) & words(obj_val(ast)) > 0

quasiquote: procedure expose values. env. err /* quasiquote(ast) */
  ast = arg(1)
  if \pair?(ast) then return new_list(new_symbol("quote") || " " || ast)
  ast0 = word(obj_val(ast), 1)
  if symbol?(ast0) & obj_val(ast0) == "unquote" then return word(obj_val(ast), 2)
  ast00 = word(obj_val(ast0), 1)
  if pair?(ast0) & symbol?(ast00) & obj_val(ast00) == "splice-unquote" then
    return new_list(new_symbol("concat") || " " || word(obj_val(ast0), 2) || " " || quasiquote(mal_rest(ast)))
  else
    return new_list(new_symbol("cons") || " " || quasiquote(ast0) || " " || quasiquote(mal_rest(ast)))

macro?: procedure expose values. env. /* macro?(ast, env_idx) */
  ast = arg(1)
  env_idx = arg(2)
  if \list?(ast) then return 0
  ast0 = mal_first(ast)
  if \symbol?(ast0) then return 0
  if env_find(env_idx, obj_val(ast0)) == 0 then return 0
  return func_macro?(env_get(env_idx, obj_val(ast0)))

macroexpand: procedure expose values. env. err /* macroexpand(ast, env_idx) */
  ast = arg(1)
  env_idx = arg(2)
  do while macro?(ast, env_idx)
    mac = env_get(env_idx, obj_val(mal_first(ast)))
    call_args = mal_rest(ast)
    mac_env_idx = new_env(func_env_idx(mac), func_binds(mac), call_args)
    ast = eval(func_body_ast(mac), mac_env_idx)
  end
  return ast

eval_ast: procedure expose values. env. err /* eval_ast(ast, env_idx) */
  ast = arg(1)
  env_idx = arg(2)
  type = obj_type(ast)
  val = obj_val(ast)
  select
    when type == "symb" then return env_get(env_idx, val)
    when type == "list" then do
      res = ""
      do i=1 to words(val)
        element = eval(word(val, i), env_idx)
        if element == "ERR" then return "ERR"
        if i > 1 then
          res = res || " " || element
        else
          res = element
      end
      return new_list(res)
    end
    when type == "vect" then do
      res = ""
      do i=1 to words(val)
        element = eval(word(val, i), env_idx)
        if element == "ERR" then return "ERR"
        if i > 1 then
          res = res || " " || element
        else
          res = element
      end
      return new_vector(res)
    end
    when type == "hash" then do
      res = ""
      do i=1 to words(val)
        element = eval(word(val, i), env_idx)
        if element == "ERR" then return "ERR"
        if i > 1 then
          res = res || " " || element
        else
          res = element
      end
      return new_hashmap(res)
    end
    otherwise
      return ast
    end

eval: procedure expose values. env. err /* eval(ast) */
  ast = arg(1)
  env_idx = arg(2)
  do forever
    if \list?(ast) then return eval_ast(ast, env_idx)
    ast = macroexpand(ast, env_idx)
    if \list?(ast) then return eval_ast(ast, env_idx)
    astval = obj_val(ast)
    if words(astval) == 0 then return ast
    a0sym = obj_val(word(astval, 1))
    select
      when a0sym == "def!" then do
        a1sym = obj_val(word(astval, 2))
        a2 = eval(word(astval, 3), env_idx)
        if a2 == "ERR" then return "ERR"
        return env_set(env_idx, a1sym, a2)
      end
      when a0sym == "let*" then do
        a1lst = obj_val(word(astval, 2))
        letenv_idx = new_env(env_idx)
        do i=1 to words(a1lst) by 2
          k = obj_val(word(a1lst, i))
          v = eval(word(a1lst, i + 1), letenv_idx)
          if v == "ERR" then return "ERR"
          unused = env_set(letenv_idx, k, v)
        end
        env_idx = letenv_idx
        ast = word(astval, 3)
        /* TCO */
      end
      when a0sym == "quote" then return word(astval, 2)
      when a0sym == "quasiquote" then do
        ast = quasiquote(word(astval, 2))
        /* TCO */
      end
      when a0sym == "defmacro!" then do
        a1sym = obj_val(word(astval, 2))
        a2 = eval(word(astval, 3), env_idx)
        if a2 == "ERR" then return "ERR"
        return env_set(env_idx, a1sym, func_mark_as_macro(a2))
      end
      when a0sym == "macroexpand" then return macroexpand(word(astval, 2), env_idx)
      when a0sym == "do" then do
        do i=2 to (words(astval) - 1)
          res = eval(word(astval, i), env_idx)
          if res == "ERR" then return "ERR"
        end
        ast = word(astval, words(astval))
        /* TCO */
      end
      when a0sym == "if" then do
        condval = eval(word(astval, 2), env_idx)
        if false?(condval) | nil?(condval) then
          if words(astval) >= 4 then
            ast = word(astval, 4)
          else
            return new_nil()
        else
          ast = word(astval, 3)
        /* TCO */
      end
      when a0sym == "fn*" then return new_func(word(astval, 3), env_idx, word(astval, 2))
      otherwise
        lst_obj = eval_ast(ast, env_idx)
        if lst_obj == "ERR" then return "ERR"
        lst = obj_val(lst_obj)
        f = word(lst, 1)
        select
          when nativefn?(f) then do
            call_args = subword(lst, 2)
            call_list = ""
            do i=1 to words(call_args)
              element = '"' || word(call_args, i) || '"'
              if i > 1 then
                call_list = call_list || ', ' || element
              else
                call_list = element
            end
            res = ""
            interpret "res = " || obj_val(f) || "(" || call_list || ")"
            return res
          end
          when func?(f) then do
            call_args = new_list(subword(lst, 2))
            env_idx = new_env(func_env_idx(f), func_binds(f), call_args)
            ast = func_body_ast(f)
            /* TCO */
          end
          otherwise
            err = "Unsupported function object type: " || obj_type(f)
            return "ERR"
          end
      end
  end

print: procedure expose values. /* print(ast) */
  return pr_str(arg(1), 1)

re:  procedure expose values. env. err repl_env_idx /* re(str) */
  str = arg(1)
  ast = read(str)
  if ast == "ERR" then return "ERR"
  return eval(ast, repl_env_idx)

rep: procedure expose values. env. err repl_env_idx /* rep(str) */
  str = arg(1)
  exp = re(str)
  if exp == "ERR" then return "ERR"
  return print(exp)

mal_eval: procedure expose values. env. err /* mal_eval(ast) */
  ast = arg(1)
  if ast == "ERR" then return "ERR"
  return eval(arg(1), 1) /* repl_env_idx is always 1 because it's the first env */

build_args_list: procedure expose values. command_line_args. /* build_args_list() */
  seq = ""
  do i=2 to command_line_args.0
    s = new_string(command_line_args.i)
    if i == 1 then
      seq = s
    else
      seq = seq || " " || s
  end
  return new_list(seq)

main:
  values. = ""
  values.0 = 0
  env. = ""
  env.0 = 0
  repl_env_idx = new_env(0)

  /* core.rexx: defined using Rexx */
  core_ns = get_core_ns()
  do i=1 to words(core_ns) by 2
    x = env_set(repl_env_idx, word(core_ns, i), new_nativefn(word(core_ns, i + 1)))
  end
  x = env_set(repl_env_idx, "eval", new_nativefn("mal_eval"))
  x = env_set(repl_env_idx, "*ARGV*", build_args_list())

  /* core.mal: defined using the language itself */
  x = re("(def! not (fn* (a) (if a false true)))")
  x = re('(def! load-file (fn* (f) (eval (read-string (str "(do " (slurp f) ")")))))')
  x = re("(defmacro! cond (fn* (& xs) (if (> (count xs) 0) (list 'if (first xs) (if (> (count xs) 1) (nth xs 1) (throw " || '"' || "odd number of forms to cond" || '"' || ")) (cons 'cond (rest (rest xs)))))))");

  err = ""
  if command_line_args.0 > 0 then do
    x = re('(load-file "' || command_line_args.1 || '")')
    return
  end

  do while lines() > 0 /* 1 == 1 */
    input_line = readline('user> ')
    if length(input_line) > 0 then do
      res = rep(input_line)
      if res == "ERR" then
        call lineout , "Error: " || err
      else
        call lineout , res
    end
  end
