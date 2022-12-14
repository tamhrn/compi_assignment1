#use "pc.ml";;

exception X_not_yet_implemented;;
exception X_this_should_not_happen of string;;

let rec is_member a = function
  | [] -> false
  | a' :: s -> (a = a') || (is_member a s);;

let rec gcd a b =
  match (a, b) with
  | (0, b) -> b
  | (a, 0) -> a
  | (a, b) -> gcd b (a mod b);;

type scm_number =
  | ScmRational of (int * int)
  | ScmReal of float;;

type sexpr =
  | ScmVoid
  | ScmNil
  | ScmBoolean of bool
  | ScmChar of char
  | ScmString of string
  | ScmSymbol of string
  | ScmNumber of scm_number
  | ScmVector of (sexpr list)
  | ScmPair of (sexpr * sexpr);;

module type READER = sig
  val nt_sexpr : sexpr PC.parser
  val print_sexpr : out_channel -> sexpr -> unit
  val print_sexprs : out_channel -> sexpr list -> unit
  val sprint_sexpr : 'a -> sexpr -> string
  val sprint_sexprs : 'a -> sexpr list -> string
  val scheme_sexpr_list_of_sexpr_list : sexpr list -> sexpr
end;; (* end of READER signature *)

module Reader : READER = struct
  open PC;;
  let make_make_skipped_star nt_skip nt = 
    let nt1 = caten nt_skip (caten nt nt_skip) in
    let nt1 = pack nt1 (fun (_,(e,_)) -> e) in
    nt1;;

  type string_part =
    | Static of string
    | Dynamic of sexpr;;

  let unitify nt = pack nt (fun _ -> ());;

  let rec nt_whitespace str =
    const (fun ch -> ch <= ' ') str
  and nt_end_of_line_or_file str = 
    let nt1 = unitify (char '\n') in
    let nt2 = unitify nt_end_of_input in
    let nt1 = disj nt1 nt2 in
    nt1 str
  and nt_line_comment str =
    let nt1 = char ';' in
    let nt2 = diff nt_any nt_end_of_line_or_file in
    let nt2 = star nt2 in
    let nt1 = caten nt1 nt2 in
    let nt1 = caten nt1 nt_end_of_line_or_file in
    let nt1 = unitify nt1 in
    nt1 str
  and nt_paired_comment str =
    let bracket_curly_left = unitify (char '{') in
    let bracket_curly_right = unitify (char '}') in
    let nt_one_of = unitify (one_of "{}") in
    let nt_nt_char = unitify nt_char in
    let nt_nt_string = unitify nt_string in
    let nt_nt_paired_comment = unitify nt_paired_comment in
    let disj_list_for_diff = disj_list [nt_one_of; nt_nt_char; nt_nt_string; nt_nt_paired_comment] in
    let nt_final = unitify (diff nt_any disj_list_for_diff) in
    let disj_list_for_disj = disj_list [nt_nt_char;nt_nt_string;nt_nt_paired_comment] in 
    let nt_final = disj nt_final disj_list_for_disj in 
    let nt_final = unitify (star nt_final) in
    let nt_final = caten_list [bracket_curly_left; nt_final;bracket_curly_right] in
    let nt_final = unitify nt_final in
    nt_final str
  and nt_sexpr_comment str = 
    let nt1 = caten (word "#;") nt_sexpr in
    let nt1 = pack nt1 (fun _ -> ()) in
    nt1 str
  and nt_comment str =
    disj_list
      [nt_line_comment;
       nt_paired_comment;
       nt_sexpr_comment] str
  and nt_void str =
    let nt1 = word_ci "#void" in
    let nt1 = not_followed_by nt1 nt_symbol_char in
    let nt1 = pack nt1 (fun _ -> ScmVoid) in
    nt1 str
  and nt_skip_star str =
    let nt1 = disj (unitify nt_whitespace) nt_comment in
    let nt1 = unitify (star nt1) in
    nt1 str
  and make_skipped_star (nt : 'a parser) =
    let nt1 = caten nt_skip_star (caten nt nt_skip_star) in
    let nt1 = pack nt1 (fun (_, (e, _)) -> e) in
    nt1
  and nt_digit str =
    let nt1 = range '0' '9' in
    let delta = int_of_char '0' in
    let nt1 = pack nt1 (fun ch -> int_of_char ch - delta) in
    nt1 str
  and nt_hex_digit str = 
    let nt_digit_a_f = range 'a' 'f' in
    let delta_a = int_of_char 'a' in
    let nt_digit_a_f = pack nt_digit_a_f (fun a -> int_of_char a - delta_a + 10 ) in
    let nt_digit_A_F = range 'A' 'F' in
    let delta_A = int_of_char 'A' in
    let nt_digit_A_F = pack nt_digit_A_F (fun a -> int_of_char a - delta_A + 10 ) in
    let nt_digit_final = disj_list [nt_digit;nt_digit_a_f;nt_digit_A_F] in
    nt_digit_final str 

  and nt_nat str = 
    let nt1 = plus nt_digit in 
    let nt1 = pack nt1 (fun digits -> 
                          List.fold_left
                            (fun num digit -> 
                              10 * num + digit)
                              0
                              digits) in
    nt1 str
  and nt_hex_nat str = 
    let nt1 = plus nt_hex_digit in
    let nt1 = pack nt1
                (fun digits ->
                  List.fold_left
                    (fun num digit ->
                      16 * num + digit)
                    0
                    digits) in
    nt1 str
  and nt_optional_sign str = 
    let ntPlus = pack (char '+') (fun e -> true) in
    let ntMinus = pack (char '-') (fun e -> false) in
    let nt = maybe (disj ntPlus ntMinus) in
    let nt = pack nt (fun sign -> 
                        match sign with
                        | None -> true
                        | Some(boole) -> boole) in
    nt str
  and nt_int str =
    let nt1 = caten nt_optional_sign nt_nat in
    let nt1 = pack nt1
                (fun (is_positive, n) ->
                  if is_positive then n else -n) in
    nt1 str
  and nt_frac str =
    let nt1 = caten nt_int (char '/') in
    let nt1 = pack nt1 (fun (num, _) -> num) in
    let nt2 = only_if nt_nat (fun n -> n != 0) in
    let nt1 = caten nt1 nt2 in
    let nt1 = pack nt1
                (fun (num, den) ->
                  let d = gcd num den in
                  ScmRational(num / d, den / d)) in
    nt1 str
  and nt_integer_part str =
    let nt1 = plus nt_digit in
    let nt1 = pack nt1
                (fun digits ->
                  List.fold_left
                    (fun num digit -> 10.0 *. num +. (float_of_int digit))
                    0.0
                    digits) in
    nt1 str
  and nt_mantissa str =
    let nt1 = plus nt_digit in
    let nt1 = pack nt1
                (fun digits ->
                  List.fold_right
                    (fun digit num ->
                      ((float_of_int digit) +. num) /. 10.0)
                    digits
                    0.0) in
    nt1 str
  and nt_exponent str =
    let nt1 = unitify (char_ci 'e') in
    let nt2 = word "*10" in
    let nt3 = unitify (word "**") in
    let nt4 = unitify (char '^') in
    let nt3 = disj nt3 nt4 in
    let nt2 = caten nt2 nt3 in
    let nt2 = unitify nt2 in
    let nt1 = disj nt1 nt2 in
    let nt1 = caten nt1 nt_int in
    let nt1 = pack nt1 (fun (_, n) -> Float.pow 10. (float_of_int n)) in
    nt1 str
  and make_maybe nt none_value =
    pack (maybe nt)
      (function
       | None -> none_value
       | Some(x) -> x)
  and nt_float str =
    let ntChar = char '.' in
    let ntA = pack (caten nt_integer_part ntChar) (fun (num,_) -> num) in
    let maybe_mantissa = pack (maybe nt_mantissa) (fun exp ->
      match exp with
      | None -> 0.0
      | Some(mantisaPart) -> mantisaPart) in
    let ntA = pack (caten ntA maybe_mantissa) (fun (intPart,mantisPart) -> intPart +. mantisPart) in
    let maybe_exponent = pack (maybe nt_exponent) (fun exp ->
      match exp with
      | None -> 1.0
      | Some(exponentPart) -> exponentPart) in
    let ntA = pack (caten ntA maybe_exponent) (fun (floatNum,expPart) -> floatNum *. expPart) in
    let ntB = pack (caten ntChar nt_mantissa) (fun (_,manPart) -> manPart) in
    let ntB = pack (caten ntB maybe_exponent) (fun (mantPart,expoPart)-> mantPart *. expoPart) in
    let ntC = pack (caten nt_integer_part nt_exponent) (fun (integPart,exponPart)-> integPart *. exponPart) in
    let ntFloat = disj_list [ntA;ntB;ntC] in
    let ntFloat = pack (caten nt_optional_sign ntFloat) (fun (signOpt,floatNum) ->
      if signOpt then ScmReal floatNum else ScmReal (-.floatNum)) in
    ntFloat str

  and nt_number str =
    let nt1 = nt_float in
    let nt2 = nt_frac in
    let nt3 = pack nt_int (fun n -> ScmRational(n, 1)) in
    let nt1 = disj nt1 (disj nt2 nt3) in
    let nt1 = pack nt1 (fun r -> ScmNumber r) in
    let nt1 = not_followed_by nt1 nt_symbol_char in
    nt1 str  
  and nt_boolean str =
    let nt1 = char '#' in
    let nt2 = char_ci 'f' in
    let nt2 = pack nt2 (fun _ -> ScmBoolean false) in
    let nt3 = char_ci 't' in
    let nt3 = pack nt3 (fun _ -> ScmBoolean true) in
    let nt2 = disj nt2 nt3 in
    let nt1 = caten nt1 nt2 in
    let nt1 = pack nt1 (fun (_, value) -> value) in
    let nt2 = nt_symbol_char in
    let nt1 = not_followed_by nt1 nt2 in
    nt1 str
  and nt_char_simple str =
    let nt1 = const(fun ch -> ' ' < ch) in
    let nt1 = not_followed_by nt1 nt_symbol_char in
    nt1 str
  and nt_char_named str = 
    let nt1 = pack (word_ci "newline") (fun _ -> '\n') in
    let nt2 = pack (word_ci "nul") (fun _ -> '\000') in
    let nt3 = pack (word_ci "page") (fun _ -> '\012') in
    let nt4 = pack (word_ci "return") (fun _ -> '\r') in
    let nt5 = pack (word_ci "space") (fun _ -> ' ')in
    let nt6 = pack (word_ci "tab") (fun _ -> '\t') in
    let nt7 = disj_list [nt1; nt2; nt3; nt4; nt5; nt6] in
    nt7 str
  and nt_char_hex str =
    let nt1 = caten (char_ci 'x') nt_hex_nat in
    let nt1 = pack nt1 (fun (_, n) -> n) in
    let nt1 = only_if nt1 (fun n -> n < 256) in
    let nt1 = pack nt1 (fun n -> char_of_int n) in
    nt1 str  
  and nt_char str =
    let nt1 = word "#\\" in
    let nt2 = disj nt_char_simple (disj nt_char_named nt_char_hex) in
    let nt1 = caten nt1 nt2 in
    let nt1 = pack nt1 (fun (_, ch) -> ScmChar ch) in
    nt1 str
  and nt_symbol_char str =
    let nt1 = range_ci 'a' 'z' in
    let nt1 = pack nt1 Char.lowercase_ascii in
    let nt2 = range '0' '9' in
    let nt3 = one_of "!$^*_-+=<>?/" in
    let nt1 = disj nt1 (disj nt2 nt3) in
    nt1 str
  and nt_symbol str = 
    let ntSymbol = pack (plus nt_symbol_char) (fun lst -> ScmSymbol (string_of_list lst))  in
    ntSymbol str

  and nt_string_part_simple str =
    let nt1 =
      disj_list [unitify (char '"'); unitify (char '\\'); unitify (word "~~");
                 unitify nt_string_part_dynamic] in
    let nt1 = diff nt_any nt1 in
    nt1 str
  and nt_string_part_meta str =
    let nt1 =
      disj_list [pack (word "\\\\") (fun _ -> '\\');
                 pack (word "\\\"") (fun _ -> '"');
                 pack (word "\\n") (fun _ -> '\n');
                 pack (word "\\r") (fun _ -> '\r');
                 pack (word "\\f") (fun _ -> '\012');
                 pack (word "\\t") (fun _ -> '\t');
                 pack (word "~~") (fun _ -> '~')] in
    nt1 str
  and nt_string_part_hex str =
    let nt1 = word_ci "\\x" in
    let nt2 = nt_hex_nat in
    let nt2 = only_if nt2 (fun n -> n < 256) in
    let nt3 = char ';' in
    let nt1 = caten nt1 (caten nt2 nt3) in
    let nt1 = pack nt1 (fun (_, (n, _)) -> n) in
    let nt1 = pack nt1 char_of_int in
    nt1 str
  and nt_string_part_dynamic str = 
    let nt_curly_left = caten (char '{') (star nt_whitespace) in
    let nt_curly_right = caten (star nt_whitespace) (char '}') in
    let nt_final = caten (char '~') nt_curly_left in
    let nt_final = pack (caten nt_final nt_sexpr) (fun (_,exp) -> exp) in
    let nt_final = caten nt_final nt_curly_right in
    let nt_final = pack nt_final (fun (exp,_) ->  Dynamic (ScmPair(ScmSymbol "format", ScmPair(ScmString "~a", ScmPair(exp, ScmNil))))) in
    nt_final str

  and nt_string_part_static str =
    let nt1 = disj_list [nt_string_part_simple;
                         nt_string_part_meta;
                         nt_string_part_hex] in
    let nt1 = plus nt1 in
    let nt1 = pack nt1 string_of_list in
    let nt1 = pack nt1 (fun str -> Static str) in
    nt1 str
  and nt_string_part str =
    disj nt_string_part_static nt_string_part_dynamic str
  and nt_string str =
    let nt1 = char '"' in
    let nt2 = star nt_string_part in
    let nt3 = char '"' in
    let nt1 = caten nt1 (caten nt2 nt3) in
    let nt1 = pack nt1 (fun (_, (parts, _)) -> parts) in
    let nt1 = pack nt1
                (fun parts ->
                  match parts with
                  | [] -> ScmString ""
                  | [Static(str)] -> ScmString str
                  | [Dynamic(sexpr)] -> sexpr
                  | parts ->
                     let argl =
                       List.fold_right
                         (fun car cdr ->
                           ScmPair((match car with
                                    | Static(str) -> ScmString(str)
                                    | Dynamic(sexpr) -> sexpr),
                                   cdr))
                         parts
                         ScmNil in
                     ScmPair(ScmSymbol "string-append", argl)) in
    nt1 str
  and nt_vector str = 
    let nt_start_vector = make_make_skipped_star nt_skip_star (word "#(") in
    let nt_clean_sexp = star (make_make_skipped_star nt_skip_star nt_sexpr) in
    let nt_start_vector = caten nt_start_vector nt_clean_sexp in
    let nt_start_vector = caten nt_start_vector (char ')') in
    let nt_start_vector = pack nt_start_vector (fun ((_,sexprs),_) -> ScmVector sexprs) in
    nt_start_vector str
  and nt_list str =                
    let right_brac = make_make_skipped_star nt_skip_star (char ')')in
    let left_brac =  make_make_skipped_star nt_skip_star (char '(') in
    let nt_dot = pack (caten (char '.') nt_sexpr) (fun (_,sexpr) -> sexpr) in
    let nt_dot = pack (maybe nt_dot) (fun exp ->
      match exp with
      | None -> ScmNil
      | Some (sexpr)-> sexpr)in
    let nt_final = caten left_brac (star nt_sexpr) in
    let nt_final = caten nt_final nt_dot in
    let nt_final = caten nt_final right_brac in
    let nt_final = pack nt_final (fun (((_,sexprs),last),_) -> List.fold_right (fun car cdr -> ScmPair(car, cdr)) sexprs last) in
    nt_final str
    
  and make_quoted_form nt_qf qf_name =
    let nt1 = caten nt_qf nt_sexpr in
    let nt1 = pack nt1
                (fun (_, sexpr) ->
                  ScmPair(ScmSymbol qf_name,
                          ScmPair(sexpr, ScmNil))) in
    nt1
  and nt_quoted_forms str =
    let nt1 =
      disj_list [(make_quoted_form (unitify (char '\'')) "quote");
                 (make_quoted_form (unitify (char '`')) "quasiquote");
                 (make_quoted_form
                    (unitify (not_followed_by (char ',') (char '@')))
                    "unquote");
                 (make_quoted_form (unitify (word ",@")) "unquote-splicing")] in
    nt1 str
  and nt_sexpr str = 
    let nt1 =
      disj_list [nt_void; nt_number; nt_boolean; nt_char; nt_symbol;
                 nt_string; nt_vector; nt_list; nt_quoted_forms] in
    let nt1 = make_skipped_star nt1 in
    nt1 str;;

  let rec string_of_sexpr = function
    | ScmVoid -> "#<void>"
    | ScmNil -> "()"
    | ScmBoolean(false) -> "#f"
    | ScmBoolean(true) -> "#t"
    | ScmChar('\n') -> "#\\newline"
    | ScmChar('\r') -> "#\\return"
    | ScmChar('\012') -> "#\\page"
    | ScmChar('\t') -> "#\\tab"
    | ScmChar(' ') -> "#\\space"
    | ScmChar(ch) ->
       if (ch < ' ')
       then let n = int_of_char ch in
            Printf.sprintf "#\\x%x" n
       else Printf.sprintf "#\\%c" ch
    | ScmString(str) ->
       Printf.sprintf "\"%s\""
         (String.concat ""
            (List.map
               (function
                | '\n' -> "\\n"
                | '\012' -> "\\f"
                | '\r' -> "\\r"
                | '\t' -> "\\t"
                | '\"' -> "\\\""
                | ch ->
                   if (ch < ' ')
                   then Printf.sprintf "\\x%x;" (int_of_char ch)
                   else Printf.sprintf "%c" ch)
               (list_of_string str)))
    | ScmSymbol(sym) -> sym
    | ScmNumber(ScmRational(0, _)) -> "0"
    | ScmNumber(ScmRational(num, 1)) -> Printf.sprintf "%d" num
    | ScmNumber(ScmRational(num, -1)) -> Printf.sprintf "%d" (- num)
    | ScmNumber(ScmRational(num, den)) -> Printf.sprintf "%d/%d" num den
    | ScmNumber(ScmReal(x)) -> Printf.sprintf "%f" x
    | ScmVector(sexprs) ->
       let strings = List.map string_of_sexpr sexprs in
       let inner_string = String.concat " " strings in
       Printf.sprintf "#(%s)" inner_string
    | ScmPair(ScmSymbol "quote",
              ScmPair(sexpr, ScmNil)) ->
       Printf.sprintf "'%s" (string_of_sexpr sexpr)
    | ScmPair(ScmSymbol "quasiquote",
              ScmPair(sexpr, ScmNil)) ->
       Printf.sprintf "`%s" (string_of_sexpr sexpr)
    | ScmPair(ScmSymbol "unquote",
              ScmPair(sexpr, ScmNil)) ->
       Printf.sprintf ",%s" (string_of_sexpr sexpr)
    | ScmPair(ScmSymbol "unquote-splicing",
              ScmPair(sexpr, ScmNil)) ->
       Printf.sprintf ",@%s" (string_of_sexpr sexpr)
    | ScmPair(car, cdr) ->
       string_of_sexpr' (string_of_sexpr car) cdr
  and string_of_sexpr' car_string = function
    | ScmNil -> Printf.sprintf "(%s)" car_string
    | ScmPair(cadr, cddr) ->
       let new_car_string =
         Printf.sprintf "%s %s" car_string (string_of_sexpr cadr) in
       string_of_sexpr' new_car_string cddr
    | cdr ->
       let cdr_string = (string_of_sexpr cdr) in
       Printf.sprintf "(%s . %s)" car_string cdr_string;;

  let print_sexpr chan sexpr = output_string chan (string_of_sexpr sexpr);;

  let print_sexprs chan sexprs =
    output_string chan
      (Printf.sprintf "[%s]"
         (String.concat "; "
            (List.map string_of_sexpr sexprs)));;

  let sprint_sexpr _ sexpr = string_of_sexpr sexpr;;

  let sprint_sexprs chan sexprs =
    Printf.sprintf "[%s]"
      (String.concat "; "
         (List.map string_of_sexpr sexprs));;

  let scheme_sexpr_list_of_sexpr_list sexprs =
    List.fold_right (fun car cdr -> ScmPair (car, cdr)) sexprs ScmNil;;

end;; (* end of struct Reader *)