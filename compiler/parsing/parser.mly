%{

open Lexing
open Location
open Parsetree

let localise start_pos end_pos = Loc(start_pos.pos_cnum, end_pos.pos_cnum)

let make desc start_pos end_pos =
  { desc = desc; loc = localise start_pos end_pos }

let make_name op start_pos end_pos =
  make (Evar(Name(op))) start_pos end_pos

let unop op e start_pos end_pos = Eapp(make_name op start_pos end_pos, [e])
let binop op e1 e2 start_pos end_pos =
  Eapp(make_name op start_pos end_pos, [e1; e2])

let unary_minus op e start_pos end_pos =
  match op, e.desc with
    | "-", Econst(Eint v) -> Econst(Eint(-v))
    | ("-" | "_."), Econst(Efloat v) -> Econst(Efloat(-.v))
    | _ -> unop ("~" ^ op) e start_pos end_pos

let unary_minus_int x = -x
and unary_minus_float x = -.x

let no_eq start_pos end_pos = make (EQempty) start_pos end_pos

(* constructors with arguments *)
let app f l =
  match f.desc, l with
  | Econstr0(id), [{ desc = Etuple(arg_list) }] ->
     (* C(e1,...,en) *)
     Econstr1(id, arg_list)
  | Econstr0(id), [arg] ->
     Econstr1(id, [arg])
  | _ -> Eapp(f, l)
		     
let constr f e =
  match e.desc with
  | Etuple(arg_list) ->
    (* C(e1,...,en) *) Econstr1(f, arg_list)
  | _ ->
     (* C(e) *) Econstr1(f, [e])

let constr_pat f p =
  match p.desc with
  | Etuplepat(arg_list) ->
    (* C(p1,...,pn) *) Econstr1pat(f, arg_list)
  | _ ->
     (* C(p) *) Econstr1pat(f, [p])

let scond_true start_pos end_pos =
  make (Econdexp(make (Econst(Ebool(true))) start_pos end_pos))
       start_pos end_pos

%}

%token <string> CONSTRUCTOR
%token <string> IDENT
%token <int> INT
%token <float> FLOAT
%token <bool> BOOL
%token <string> STRING
%token <char> CHAR

%token AMPERAMPER     /* "&&" */
%token AMPERSAND      /* "&" */
%token AND            /* "and" */
%token AS             /* "as" */
%token ASSERT         /* "assert" */
%token ATOMIC         /* "atomic" */
%token AUTOMATON      /* "automaton" */
%token BAR            /* "|" */
%token BARBAR         /* "||" */
%token CLOCK          /* "clock" */
%token COLON          /* ":" */
%token COMMA          /* "," */
%token CONTINUE       /* "continue" */
%token DEFAULT        /* "default" */
%token DO             /* "do" */
%token DONE           /* "done" */
%token DOT            /* "." */
%token ELSE           /* "else" */
%token EMIT           /* "emit" */
%token END            /* "end" */
%token EQUAL          /* "=" */
%token EQUALEQUAL     /* "==" */
%token EQUALGREATER   /* "=>" */
%token EVERY          /* "every" */
%token EXCEPTION      /* "exception" */
%token EXTERNAL       /* "external" */
%token FBY            /* "fby" */
%token FUN            /* "fun" */
%token GREATER        /* ">" */
%token IF             /* "if" */
%token IN             /* "in" */
%token INIT           /* "init" */
%token INLINE         /* "inline" */
%token LAST           /* "last" */
%token LBRACE         /* "{" */
%token LET            /* "let" */
%token LOCAL          /* "local" */
%token LPAREN         /* "(" */
%token MATCH          /* "match" */
%token MINUS          /* "-" */
%token MINUSGREATER   /* "->" */
%token NODE           /* "node" */
%token NOT            /* "not" */
%token OF             /* "of" */
%token ON             /* "on" */
%token OPEN           /* "open" */
%token OR             /* "or" */
%token PLUS           /* "+" */
%token PRE            /* "pre" */
%token PRESENT        /* "present" */
%token QUOTE          /* "'" */
%token RBRACE         /* "}" */
%token REC            /* "rec" */
%token RESET          /* "reset" */
%token RETURNS        /* "returns" */
%token RPAREN         /* ")" */
%token RUN            /* ")" */
%token SEMI           /* ";" */
%token STAR           /* "*" */
%token THEN           /* "then" */
%token TYPE           /* "type" */
%token UNDERSCORE     /* "_" */
%token UNLESS         /* "unless" */
%token UNTIL          /* "until" */
%token VAL            /* "val" */
%token WHERE          /* "where" */
%token WITH           /* "with" */

%token <string> PREFIX
%token <string> INFIX0
%token <string> INFIX1
%token <string> INFIX2
%token <string> SUBTRACTIVE
%token <string> INFIX3
%token <string> INFIX4
%token EOF

%nonassoc prec_seq
%right SEMI
%nonassoc prec_ident
%right prec_list
%nonassoc ELSE
%left  AS
%left  BAR
%left COMMA
%left RPAREN
%right MINUSGREATER EQUALGREATER
%left OR BARBAR
%left AMPERSAND AMPERAMPER
%left INFIX0 GREATER EQUAL
%right INFIX1
%left INFIX2 PLUS SUBTRACTIVE MINUS
%left STAR INFIX3
%left INFIX4
%left ON
%right prec_uminus
%right FBY
%right NOT
%right PREFIX
%right PRE 
%left DOT

%start implementation_file
%type <Parsetree.implementation list> implementation_file

%start interface_file
%type <Parsetree.interface list> interface_file

%start scalar_interface_file
%type <Parsetree.interface list> scalar_interface_file

%%

/** Tools **/

/* Separated list */
list_aux(S, X):
| x = X { [x] }
| r = list_aux(S, X) S x = X { x :: r }
;

%inline list_of(S, X):
   r = list_aux(S, X) { List.rev r }
;

/* Non separated list */
list_aux_no_sep(X):
| x = X { [x] }
| r = list_aux_no_sep(X) x = X { x :: r }
;

%inline list_no_sep_of(X):
   r = list_aux_no_sep(X) { List.rev r }
;

/* Localization */
localized(X):
| x = X { make x $startpos $endpos }
;

%inline optional(X):
  | /* empty */
      { None }
  | x = X
      { Some(x) }
;

/* Interface */
interface_file:
  | EOF
      { [] }
  | il = decl_list(localized(interface)) EOF
      { List.rev il }
;

interface:
  | OPEN c = CONSTRUCTOR
      { Einter_open(c) }
  | TYPE tp = type_params i = IDENT td = localized(type_declaration_desc)
      { Einter_typedecl(i, tp, td) }
  | VAL i = ide COLON t = type_expression
      { Einter_constdecl(i, t, []) }
;

/* Scalar interface */
scalar_interface_file:
  | EOF
      { [] }
  | il = decl_list(scalar_interface) EOF
      { List.rev (List.flatten il) }
  ;

scalar_interface :
  | OPEN c = CONSTRUCTOR
      { [make (Einter_open(c)) $startpos $endpos] }
  | TYPE tp = type_params i = IDENT td = localized(type_declaration_desc)
      { [make (Einter_typedecl(i, tp, td)) $startpos $endpos] }
  | VAL i = ide COLON t = type_expression
      { [make (Einter_constdecl(i, t, [])) $startpos $endpos] }
  | EXTERNAL i = ide COLON t = type_expression EQUAL l = list_no_sep_of(STRING)
      { [make (Einter_constdecl(i, t, l)) $startpos $endpos] }
  | EXCEPTION constructor
      { [] }
  | EXCEPTION constructor OF type_expression
      { [] }
;

type_declaration_desc:
  | /* empty */
      { Eabstract_type }
  | EQUAL l = list_of(BAR, localized(constr_decl_desc))
      { Evariant_type (l) }
  | EQUAL BAR l = list_of(BAR, localized(constr_decl_desc))
      { Evariant_type (l) }
  | EQUAL LBRACE s = label_list(label_type) RBRACE
      { Erecord_type (s) }
  | EQUAL t = type_expression
      { Eabbrev(t) }
;

type_params :
  | LPAREN tvl = list_of(COMMA, type_var) RPAREN
      { tvl }
  | tv = type_var
      { [tv] }
  |
      { [] }
;

label_list(X):
  | x = X
      { [x] }
  | x = X SEMI
      { [x] }
  | x = X SEMI ll = label_list(X)
      { x :: ll }
;

label_type:
  i = IDENT COLON t = type_expression
  { (i, t) }
;

constr_decl_desc:
  | c = CONSTRUCTOR
      { Econstr0decl(c) }
  | c = CONSTRUCTOR OF l = list_of(STAR, simple_type)
      { Econstr1decl(c, l) }
;

implementation_file:
  | EOF
      { [] }
  | i = decl_list(localized(implementation)) EOF
      { List.rev i }
;

decl_list(X):
  | dl = decl_list(X) x = X
      { x :: dl }
  | x = X 
      { [x] }
;

implementation:
  | OPEN c = CONSTRUCTOR
    { Eopen c }
  | TYPE tp = type_params id = IDENT td = localized(type_declaration_desc)
      { Etypedecl(id, tp, td) }
  | LET ide = ide EQUAL seq = seq_expression
      { Eletdecl(ide, seq) }
  | LET a = is_atomic k = kind ide = ide 
        p_list = param_list r = result
    { Eletdecl(ide,
	       make (Efun(make { f_atomic = a;
				 f_kind = k; f_args = p_list; f_body = r }
			  $startpos $endpos))
	       $startpos $endpos) }
;

%inline is_atomic:
  | ATOMIC { true }
  | { false }
;

%inline kind:
  |      { Kfun }
  | FUN  { Kfun }
  | NODE { Knode }
;

%inline result:
  | RETURNS p = param eq = equation
    { make (Returns(p, eq)) $startpos $endpos }
  | EQUAL seq = seq_expression
    { make (Exp(seq)) $startpos $endpos }
  | EQUAL seq = seq_expression WHERE i = is_rec eq = equation
    { make (Exp(make (Elet(i, eq, seq)) $startpos(seq) $endpos(eq)))
      $startpos $endpos }
;

%inline equation_and_list:
  | l_opt = optional(list_of(AND, equation))
    { match l_opt with | None -> make EQempty $startpos $endpos
		       | Some([eq]) -> eq | Some(l) -> make (EQand(l)) $startpos $endpos }
;

%inline equation:
   eq = localized(equation_desc) { eq }
;

equation_desc:
  | AUTOMATON opt_bar a = automaton_handlers END
    { EQautomaton(List.rev a, None) }
  | AUTOMATON opt_bar a = automaton_handlers INIT e = state END
    { EQautomaton(List.rev a, Some(e)) }
  | MATCH e = seq_expression WITH opt_bar
    m = match_handlers(equation) END
    { EQmatch(e, List.rev m) }
  | IF e = seq_expression THEN eq1 = equation ELSE eq2 = equation END
    { EQif(e, eq1, eq2) }
  | IF e = seq_expression THEN eq1 = equation END
      { EQif(e, eq1, no_eq $startpos $endpos) }
  | IF e = seq_expression ELSE eq2 = equation END
      { EQif(e, no_eq $startpos $endpos, eq2) }
  | PRESENT opt_bar p = present_handlers(equation) END
    { EQpresent(List.rev p, NoDefault) }
  | PRESENT opt_bar p = present_handlers(equation)
    ELSE eq = equation END
    { EQpresent(List.rev p, Else(eq)) }
  | PRESENT opt_bar p = present_handlers(equation) INIT eq = equation END
    { EQpresent(List.rev p, Init(eq)) }
  | RESET eq = equation EVERY e = expression
    { EQreset(eq, e) }
  | LOCAL v_list = vardec_comma_list DO eq = equation DONE
    { EQlocal(v_list, eq) }
  | DO eq = equation_and_list DONE
    { eq.desc }
  | p = pattern EQUAL e = seq_expression
    { EQeq(p, e) }
  | INIT i = ide EQUAL e = seq_expression
    { EQinit(i, e) }
  | EMIT i = ide
      { EQemit(i, None) }
  | EMIT i = ide EQUAL e = seq_expression
      { EQemit(i, Some(e)) }
  | ASSERT e = seq_expression
    { EQassert(e) }
;

/* states of an automaton in an equation*/
automaton_handlers:
  | a = automaton_handler
      { [a] }
  | ahs = automaton_handlers BAR a = automaton_handler
      { a :: ahs }
;

automaton_handler:
  | sp = state_pat MINUSGREATER v_list_eq = vardec_with_and_eq_list DONE
    { make { s_state = sp; s_vars = fst v_list_eq; s_body = snd v_list_eq;
	     s_until = []; s_unless = [] } $startpos $endpos } 
  | sp = state_pat MINUSGREATER v_list_eq = vardec_with_and_eq_list THEN
                                e = emission
    { let v_list_e, body_e, st_e = e in
      make { s_state = sp; s_vars = fst v_list_eq; s_body = snd v_list_eq;
	     s_until =
               [make { e_cond = scond_true $endpos(v_list_eq) $startpos(e);
                       e_reset = true; e_vars = v_list_e;
		       e_body = body_e;
		       e_next_state = st_e }
		$endpos(v_list_eq) $endpos(e) ];
	     s_unless = [] } $startpos $endpos }
  | sp = state_pat MINUSGREATER v_list_eq = vardec_with_and_eq_list CONTINUE
                                e = emission
    { let v_list_e, body_e, st_e = e in
      make { s_state = sp; s_vars = fst v_list_eq; s_body = snd v_list_eq;
	     s_until =
               [make { e_cond = scond_true $endpos(v_list_eq) $startpos(e);
                       e_reset = false; e_vars = v_list_e;
		       e_body = body_e;
		       e_next_state = st_e } $endpos(v_list_eq) $endpos(e)];
	   s_unless = [] } $startpos $endpos }
  | sp = state_pat MINUSGREATER v_list_eq = vardec_with_and_eq_list
         UNTIL el = list_of(UNTIL, escape)
    { make { s_state = sp; s_vars = fst v_list_eq; s_body = snd v_list_eq;
	     s_until = el; s_unless = [] }
      $startpos $endpos }
  | sp = state_pat MINUSGREATER v_list_eq = vardec_with_and_eq_list
         UNLESS el = list_of(UNLESS, escape)
    { make { s_state = sp; s_vars = fst v_list_eq; s_body = snd v_list_eq;
	     s_until = []; s_unless = el }
      $startpos $endpos }
;

escape :
  | sc = scondpat THEN e = emission
    { let e_vars, e_body, s = e in
      make { e_cond = sc; e_reset = true;
	     e_vars = e_vars; e_body = e_body; e_next_state = s }
      $startpos $endpos }
  | sc = scondpat CONTINUE e = emission
    { let e_vars, e_body, s = e in
      make { e_cond = sc; e_reset = false;
	     e_vars = e_vars; e_body = e_body; e_next_state = s }
      $startpos $endpos }
;

state :
  | c = CONSTRUCTOR
      { make (Estate0(c)) $startpos $endpos }
  | c = CONSTRUCTOR LPAREN e = expression RPAREN
      { make (Estate1(c, [e])) $startpos $endpos }
  | c = CONSTRUCTOR LPAREN l = expression_comma_list RPAREN
    { make (Estate1(c, List.rev l)) $startpos $endpos }
  | IF e = expression THEN s1 = state ELSE s2 = state
    { make (Estateif(e, s1, s2)) $startpos $endpos }
;

state_pat :
  | c = CONSTRUCTOR
      { make (Estate0pat(c)) $startpos $endpos }
  | c = CONSTRUCTOR LPAREN l = list_of(COMMA, IDENT) RPAREN
      { make (Estate1pat(c, l)) $startpos $endpos }
;

/* Pattern on a signal */
scondpat :
  | sc = localized(scondpat_desc) { sc }
;

scondpat_desc :
  | e = simple_expression p = simple_pattern
      { Econdpat(e, p) }
  | e = simple_expression
      { Econdexp(e) }
  | scpat1 = scondpat AMPERSAND scpat2 = scondpat
      { Econdand(scpat1, scpat2) }
  | scpat1 = scondpat BAR scpat2 = scondpat
      { Econdor(scpat1, scpat2) }
  | scpat1 = scondpat ON e = simple_expression
      { Econdon(scpat1, e) }
;

/* Block */
vardec_with_and_eq_list:
  | DO eq = equation_and_list
    { [], eq }
  | LOCAL v_list = vardec_comma_list DO eq = equation_and_list
    { v_list, eq }
;

emission:
  | v_list_eq = vardec_with_and_eq_list IN s = state
    { let v_list, eq = v_list_eq in v_list, eq, s }
  | s = state
    { [], no_eq $startpos $endpos, s }
;

%inline vardec_comma_list:
  | l = list_of(COMMA, vardec)
    { l }
;

%inline vardec_empty_comma_list:
  | l = optional(vardec_comma_list)
    { match l with None -> [] | Some(l) -> l }
;


%inline param_list:
  | l = list_no_sep_of(param)
    { l }
;

%inline param:
  | LPAREN v = vardec_empty_comma_list RPAREN
    { v }
  | ide = ide
    { [ make { var_name = ide; var_clock = false;
	       var_init = None; var_default = None; var_typeconstraint = None }
	$startpos $endpos ] }
;

%inline vardec:
  | c = optional(CLOCK) ide = ide t_opt = optional(colon_type_expression)
    i_opt = optional(init_expression)
    d_opt = optional(default_expression)
    { make { var_name = ide;
	     var_clock = (match c with | None -> false | Some _ -> true);
	     var_init = i_opt; var_default = d_opt;
	     var_typeconstraint = t_opt }
      $startpos $endpos }
;

colon_type_expression:
  | COLON t = type_expression
    { t }
;

init_expression:
  | INIT e = simple_expression
    { e }
;

default_expression:
  | DEFAULT e = simple_expression
    { e }
;

opt_bar:
  | BAR             { () }
  | /*epsilon*/     { () }
;

/* Testing the presence of a signals */
present_handlers(X):
  | p = present_handler(X)
      { [ p ] }
  | ps = present_handlers(X) BAR p = present_handler(X)
      { p :: ps }
;

present_handler(X):
  | sc = scondpat MINUSGREATER x = X
      { make { p_cond = sc; p_body = x } $startpos $endpos }
;
/* Pattern matching */
match_handlers(X):
  | m = match_handler(X)
      { [ m ] }
  | mh = match_handlers(X) BAR m = match_handler(X)
      { m :: mh }
;

match_handler(X):
  | p = pattern MINUSGREATER eq = X
      { make { m_pat = p; m_body = eq } $startpos $endpos }
;

/* Patterns */
pattern:
  | p = simple_pattern
      { p }
  | p = pattern AS i = IDENT
      { make (Ealiaspat(p, i)) $startpos $endpos }
  | p1 = pattern BAR p2 = pattern
      { make (Eorpat(p1, p2)) $startpos $endpos }
  | p = pattern_comma_list %prec prec_list
      { make (Etuplepat(List.rev p)) $startpos $endpos }
  | c = constructor p = simple_pattern
      { make (constr_pat c p) $startpos $endpos }
;

simple_pattern:
  | a = atomic_constant
      { make (Econstpat a) $startpos $endpos }
  | MINUS i = INT
      { make (Econstpat(Eint(unary_minus_int i))) $startpos $endpos }
  | MINUS f = FLOAT
      { make (Econstpat(Efloat(unary_minus_float f))) $startpos $endpos }
  | c = constructor
      { make (Econstr0pat(c)) $startpos $endpos }
  | i = ide
      { make (Evarpat i) $startpos $endpos }
  | LPAREN p = pattern RPAREN
      { p }
  | LPAREN p = pattern_comma_list RPAREN
      { make (Etuplepat (List.rev p)) $startpos $endpos }
  | LPAREN RPAREN
      { make (Econstpat(Evoid)) $startpos $endpos }
  | UNDERSCORE
      { make Ewildpat $startpos $endpos }
  | LPAREN p = pattern COLON t = type_expression RPAREN
      { make (Etypeconstraintpat(p, t)) $startpos $endpos }
  | LBRACE p = pattern_label_list RBRACE
      { make (Erecordpat(p)) $startpos $endpos }
;

pattern_comma_list:
  | p1 = pattern COMMA p2 = pattern
      { [p2; p1] }
  | pc = pattern_comma_list COMMA p = pattern
      { p :: pc }
;

pattern_label_list :
  | p = pattern_label SEMI pl = pattern_label_list
      { p :: pl }
  | p = pattern_label
      { [p] }
  | UNDERSCORE
      { [] }
  | /*epsilon*/
      { [] }
;

pattern_label :
  | ei = ext_ident EQUAL p = pattern
      { (ei, p) }
;

/* Expressions */
seq_expression :
  | e = expression SEMI seq = seq_expression
      { make (Eop(Eseq, [e; seq])) $startpos $endpos }
  | e = expression %prec prec_seq
      { e }
;


%inline simple_expression_list:
  | l = list_no_sep_of(simple_expression)
    { l }
;


simple_expression:
  | desc = simple_expression_desc
      { make desc $startpos $endpos }
;

simple_expression_desc:
  | c = constructor
      { Econstr0(c) }
  | i = ext_ident
      { Evar i }
  | LAST i = ide
      { Elast(i) }
  | a = atomic_constant
      { Econst a }
  | LPAREN RPAREN
      { Econst Evoid }
  | LPAREN e = expression_comma_list RPAREN
      { Etuple (List.rev e) }
  | LPAREN e = seq_expression RPAREN
    { e.desc }
  | LBRACE l = label_expression_list RBRACE
      { Erecord(l) }
  | LBRACE e = simple_expression WITH l = label_expression_list RBRACE
    { Erecord_with(e, l) }
  | e = simple_expression DOT i = ext_ident
      { Erecord_access(e, i) }
  | LPAREN e = simple_expression COLON t = type_expression RPAREN
      { Etypeconstraint(e, t) }
  
  
;

expression_comma_list :
  | ecl = expression_comma_list COMMA e = expression
      { e :: ecl }
  | e1 = expression COMMA e2 = expression
      { [e2; e1] }
;

expression:
  | x = localized(expression_desc)
    { x }
;


expression_desc:
  | e = simple_expression_desc
      { e }
  | ATOMIC e = simple_expression
    { Eop(Eatomic, [e]) }
  | e = expression_comma_list %prec prec_list
      { Etuple(List.rev e) }
  | e1 = expression FBY e2 = expression
      { Eop(Efby, [e1; e2]) }
  | i = is_inline RUN f = simple_expression e = simple_expression
      { Eop(Erun(i), [f; e]) }
  | f = simple_expression arg_list = simple_expression_list
      { app f arg_list }
  | a = is_atomic FUN p_list = param_list k = arrow e = expression
      { Efun (make { f_atomic = a; f_kind = k;
		     f_args = p_list;
		     f_body = make (Exp(e)) $startpos(e) $endpos(e) }
	      $startpos $endpos) }
  | PRE e = expression
      { Eop(Eunarypre, [e]) }
  | IF e1 = seq_expression THEN e2 = seq_expression ELSE e3 = expression
      { Eop(Eifthenelse, [e1; e2; e3]) }
  | e1 = expression MINUSGREATER e2 = expression
      { Eop(Eminusgreater, [e1; e2]) }
  | MINUS e = expression  %prec prec_uminus
      { unary_minus "-" e ($startpos($1)) ($endpos($1)) }
  | NOT e = expression
      { unop "not" e ($startpos($1)) ($endpos($1)) }
  | s = SUBTRACTIVE e = expression  %prec prec_uminus
      { unary_minus s e ($startpos(s)) ($endpos(s)) }
  | e1 = expression i = INFIX4 e2 = expression
      { binop i e1 e2 ($startpos(i)) ($endpos(i)) }
  | e1 = expression i = INFIX3 e2 = expression
      { binop i e1 e2 ($startpos(i)) ($endpos(i)) }
  | e1 = expression i = INFIX2 e2 = expression
      { binop i e1 e2 ($startpos(i)) ($endpos(i)) }
  | e1 = expression PLUS e2 = expression
      { binop "+" e1 e2 ($startpos($2)) ($endpos($2)) }
  | e1 = expression i = INFIX1 e2 = expression
      { binop i e1 e2 ($startpos(i)) ($endpos(i)) }
  | e1 = expression i = INFIX0 e2 = expression
      { binop i e1 e2 ($startpos(i)) ($endpos(i)) }
  | e1 = expression GREATER e2 = expression
      { binop ">" e1 e2 $startpos $endpos }
  | e1 = expression EQUAL e2 = expression
      { binop "=" e1 e2 ($startpos($2)) ($endpos($2)) }
  | e1 = expression OR e2 = expression
      { binop "or" e1 e2 ($startpos($2)) ($endpos($2)) }
  | e1 = expression STAR e2 = expression
      { binop "*" e1 e2 ($startpos($2)) ($endpos($2)) }
  | e1 = expression AMPERSAND e2 = expression
      { binop "&" e1 e2 ($startpos($2)) ($endpos($2)) }
  | e1 = expression MINUS e2 = expression
      { binop "-" e1 e2 ($startpos($2)) ($endpos($2)) }
  | e1 = expression s = SUBTRACTIVE e2 = expression
      { binop s e1 e2 ($startpos(s)) ($endpos(s)) }
  | e1 = expression AMPERAMPER e2 = expression
      { binop "&&" e1 e2 ($startpos($2)) ($endpos($2)) }
  | e1 = expression BARBAR e2 = expression
      { binop "||" e1 e2 ($startpos($2)) ($endpos($2)) }
  | p = PREFIX e = expression
      { unop p e ($startpos(p)) ($endpos(p)) }
  | LET i = is_rec eq = equation IN e = seq_expression
      { Elet(i, eq, e) }
;

%inline is_inline:
  | { false }
  | INLINE { true }
;

%inline is_rec:
  | REC { true }
  |     { false }
;
constructor:
  | c = CONSTRUCTOR %prec prec_ident
      { Name(c) } 
  | c1 = CONSTRUCTOR DOT c2 = CONSTRUCTOR
      { Modname({qual = c1; id = c2}) }
;

qual_ident:
  | c = CONSTRUCTOR DOT i = ide
      { {qual = c; id = i} }
;

/* Constants */
atomic_constant:
  | i = INT
      { Eint(i) }
  | f = FLOAT
      { Efloat(f) }
  | s = STRING
      { Estring s }
  | c = CHAR
      { Echar c }
  | b = BOOL
      { Ebool b }
;

/* labels */
label_expression_list:
  | l = label_expression
      { [l] }
  | l = label_expression SEMI
      { [l] }
  | l = label_expression SEMI ll = label_expression_list
      { l :: ll }

label_expression:
  | i = ext_ident EQUAL e = expression
      { (i, e) }
;

/* identifiers */
ide:
  | i = IDENT
      { i }
  | LPAREN i = infx RPAREN
      { i }
  | LPAREN GREATER RPAREN
      { ">" }
;

ext_ident :
  | q = qual_ident
      { Modname(q) }
  | i = ide
      { Name(i) }
;

infx:
  | INFIX0          { $1 }
  | INFIX1          { $1 }    | INFIX2        { $1 }
  | INFIX3          { $1 }    | INFIX4        { $1 }
  | STAR            { "*" }
  | PLUS            { "+" }
  | MINUS           { "-" }
  | EQUAL           { "=" }
  | EQUALEQUAL      { "==" }
  | SUBTRACTIVE     { $1 }    | PREFIX        { $1 }
  | AMPERSAND       { "&" }   | AMPERAMPER    { "&&" }
  | OR              { "or" }  | BARBAR        { "||" }
  | ON              { "on" }  | NOT           { "not" }
;

%inline arrow:
  | MINUSGREATER
      { Kfun }
  | EQUALGREATER
    { Knode }
  | GREATER
    { Kstatic }
;

/* Type expressions */
type_expression:
  | t = simple_type
      { t }
  | tl = type_star_list
      { make(Etypetuple(List.rev tl)) $startpos $endpos}
  | t_arg = type_expression a = arrow t_res = type_expression
      { make(Etypefun(a, t_arg, t_res)) $startpos $endpos}
;

simple_type:
  | t = type_var
      { make (Etypevar t) $startpos $endpos }
  | i = ext_ident
      { make (Etypeconstr(i, [])) $startpos $endpos }
  | t = simple_type i = ext_ident
      { make (Etypeconstr(i, [t])) $startpos $endpos }
  | LPAREN t = type_expression COMMA tl = type_comma_list RPAREN i = ext_ident
      { make (Etypeconstr(i, t :: tl)) $startpos $endpos }
  | LPAREN t = type_expression RPAREN
      { t }
;

type_star_list:
  | t1 = simple_type STAR t2 = simple_type
      { [t2; t1] }
  | tsl = type_star_list STAR t = simple_type
      { t :: tsl }
;

type_var :
  | QUOTE i = IDENT
      { i }
;

type_comma_list :
  | te = type_expression COMMA tl = type_comma_list
      { te :: tl }
  | te = type_expression
      { [te] }
;
