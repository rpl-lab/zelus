open Obc
open Muf
open Muf_utils

exception Not_yet_implemented of string

let not_yet_implemented msg =
  raise (Not_yet_implemented msg)

let get_id x =
  begin match x with
  | Lident.Name id | Lident.Modname { Lident.id = id } -> id
  end

let is_sample x =
  get_id x = "sample"

let is_observe x =
  get_id x = "observe"

let is_factor x =
  get_id x = "factor"

let rec split_proba_patt patt_l =
  begin match patt_l with
  | Ovarpat ({ source = "prob" } as prob, _) :: l -> Some (ident prob, l)
  | Otuplepat (Ovarpat ({ source = "prob" } as prob, _) :: t) :: l ->
      Some (ident prob, Otuplepat t :: l)
  | Otypeconstraintpat (p, _) :: l -> split_proba_patt (p :: l)
  | Ovarpat _ :: _ | Owildpat :: _ | Oconstpat _ :: _ | Oaliaspat (_, _) :: _
  | Oconstr0pat _ :: _ | Oconstr1pat (_, _) :: _ | Oorpat (_, _) :: _
  | Orecordpat _ :: _ | Otuplepat _ :: _ | [] ->
      None
  end

let rec split_proba_expr expr =
  begin match expr with
  | Otuple ((Olocal ({ source = "prob" } as prob)) :: l)
  | Otuple ((Ovar (_, ({ source = "prob" } as prob))) :: l) ->
      Some (ident prob, Otuple l)
  | Otuple [ Otuple l ] -> split_proba_expr (Otuple l)
  | Otypeconstraint (e, _) -> split_proba_expr e
  | Otuple _ | Oconst _ | Oconstr0 _ | Oconstr1 (_, _)
  | Oglobal _ | Olocal _ | Ovar (_, _) | Ostate _ | Oaccess (_, _)
  | Oupdate (_, _, _, _) | Oslice (_, _, _) | Oconcat (_, _, _, _)
  | Ovec (_, _) | Oapp (_, _) | Orecord _ | Orecord_access (_, _)
  | Orecord_with (_, _) | Oifthenelse (_, _, _) | Omethodcall _ | Oinst _ ->
      None
  end

let self = { modul = None; name = "self" }
let self_patt = pvar self
let self_expr = evar self

let instance_init x =
  mk_expr (Ecall_init (mk_expr (Evar x)))

let pack vars e =
  if IdSet.is_empty vars then e
  else Etuple [ expr_of_idset vars; mk_expr e ]

let unpack vars p =
  if IdSet.is_empty vars then p
  else mk_patt (Ptuple [ patt_of_idset vars; p ])

let rec var_of_left_value v =
  begin match v with
  | Oleft_name x -> ident x
  | Oleft_record_access (v, _) -> var_of_left_value v
  | Oleft_index (v, _) -> var_of_left_value v
  end

let rec var_of_left_state_value left =
  begin match left with
  | Oself -> self
  | Oleft_instance_name(_n) -> self
  | Oleft_state_global(ln) -> lident ln
  | Oleft_state_name(_n) -> self
  | Oleft_state_record_access(left, _n) -> var_of_left_state_value left
  | Oleft_state_index(left, _idx) -> var_of_left_state_value left
  | Oleft_state_primitive_access(left, _a) -> var_of_left_state_value left
  end

let rec vars_of_pattern p =
  begin match p with
  | Owildpat -> IdSet.empty
  | Otuplepat l ->
      List.fold_left
        (fun acc p -> IdSet.union (vars_of_pattern p) acc)
        IdSet.empty l
  | Ovarpat (x, _) -> IdSet.singleton (ident x)
  | Oconstpat _ -> IdSet.empty
  | Oaliaspat (p, x) ->
      IdSet.union (IdSet.singleton (ident x)) (vars_of_pattern p)
  | Oconstr0pat _ -> IdSet.empty
  | Oconstr1pat (_, l) ->
      List.fold_left
        (fun acc p -> IdSet.union (vars_of_pattern p) acc)
        IdSet.empty l
  | Oorpat (p1, p2) -> IdSet.union (vars_of_pattern p1) (vars_of_pattern p2)
  | Otypeconstraintpat (p, _) -> vars_of_pattern p
  | Orecordpat l ->
      List.fold_left
        (fun acc (_, p) -> IdSet.union (vars_of_pattern p) acc)
        IdSet.empty l
  end

let rec fv_updated i =
  begin match i with
  | Olet(_p, e, i) -> IdSet.union (fv_expr_updated e) (fv_updated i)
  | Oletvar(x, _is_mutable, _ty, e_opt, i) ->
      IdSet.union (Option.fold ~none:IdSet.empty ~some:fv_expr_updated e_opt)
        (IdSet.remove (ident x) (fv_updated i))
  | Omatch(e, match_handler_l) ->
      List.fold_left
        (fun acc { w_pat = p; w_body = i } ->
          let fvs = IdSet.diff (fv_updated i) (vars_of_pattern p)  in
          IdSet.union acc fvs)
        (fv_expr_updated e) match_handler_l
  | Ofor(_is_to, _n, e1, e2, i3) ->
      IdSet.union (fv_expr_updated e1)
        (IdSet.union (fv_expr_updated e2) (fv_updated i3))
  | Owhile(e1, i2) -> IdSet.union (fv_expr_updated e1) (fv_updated i2)
  | Oassign(x, e) -> IdSet.add (var_of_left_value x) (fv_expr_updated e)
  | Oassign_state(left, e) ->
      IdSet.add (var_of_left_state_value left) (fv_expr_updated e)
  | Osequence l ->
      List.fold_left (fun acc i -> IdSet.union (fv_updated i) acc) IdSet.empty l
  | Oexp(e) -> fv_expr_updated e
  | Oif(e, i1, None) -> IdSet.union (fv_expr_updated e) (fv_updated i1)
  | Oif(e, i1, Some i2) ->
      IdSet.union (fv_expr_updated e)
        (IdSet.union (fv_updated i1) (fv_updated i2))
  end

and fv_expr_updated expr =
  begin match expr with
  | Oconst _ -> IdSet.empty
  | Oconstr0 _ -> IdSet.empty
  | Oconstr1 (_, e_list) ->
      List.fold_left (fun acc e -> IdSet.union (fv_expr_updated e) acc)
        IdSet.empty e_list
  | Oglobal _ -> IdSet.empty
  | Olocal _ -> IdSet.empty
  | Ovar(_is_mutable, n) -> IdSet.empty
  | Ostate(l) -> IdSet.empty
  | Oaccess(e, eidx) ->
      IdSet.union (fv_expr_updated e) (fv_expr_updated eidx)
  | Ovec(e, _se) -> fv_expr_updated e
  | Oupdate(_se, _e1, _i, _e2) -> not_yet_implemented "fv_update: update"
  | Oslice(_e, _s1, _s2) -> not_yet_implemented "fv_update: slice"
  | Oconcat(_e1, _s1, _e2, _s2) -> not_yet_implemented "fv_update: concat"
  | Otuple(e_list) ->
      List.fold_left (fun acc e -> IdSet.union (fv_expr_updated e) acc)
        IdSet.empty e_list
  | Oapp(e, e_list) ->
      List.fold_left (fun acc e -> IdSet.union (fv_expr_updated e) acc)
        (fv_expr_updated e) e_list
  | Omethodcall m ->
      let fvs =
        List.fold_left (fun acc e -> IdSet.union (fv_expr_updated e) acc)
          IdSet.empty m.met_args
      in
      let fvs =
        begin match m.met_machine with
        | Some x when is_sample x || is_observe x || is_factor x -> fvs
        | _ -> IdSet.add self fvs
        end
      in
      begin match split_proba_expr (Otuple m.met_args) with
      | None -> fvs
      | Some (prob, _) -> IdSet.add prob fvs
      end
  | Orecord(r) ->
      List.fold_left (fun acc (_, e) -> IdSet.union (fv_expr_updated e) acc)
        IdSet.empty r
  | Orecord_with(e_record, r) ->
      List.fold_left (fun acc (_, e) -> IdSet.union (fv_expr_updated e) acc)
        (fv_expr_updated e_record) r
  | Orecord_access(e_record, lname) -> fv_expr_updated e_record
  | Otypeconstraint(e, _ty_e) -> fv_expr_updated e
  | Oifthenelse(e, e1, e2) ->
      IdSet.union (fv_expr_updated e)
        (IdSet.union (fv_expr_updated e1) (fv_expr_updated e2))
  | Oinst(i) -> fv_updated i
  end


(* Compilation functions *)

let immediate c =
  begin match c with
  | Oint i -> Cint i
  | Oint32 i -> Cint32 (Int32.of_int i)
  | Ofloat f -> Cfloat (string_of_float f)
  | Obool b -> Cbool b
  | Ostring s -> Cstring s
  | Ochar c -> Cchar c
  | Ovoid -> Cunit
  | Oany -> Cany
  end

let rec type_expression t =
  match t with
  | Otypevar x -> Tvar x
  | Otypefun _ -> assert false (* XXX TODO XXX *)
  | Otypetuple l -> Ttuple (List.map type_expression l)
  | Otypeconstr (x, args) ->
      Tconstr (Lident.source x, List.map type_expression args)
  | Otypevec _ -> not_yet_implemented "type_expression(vec)"

let rec pattern patt =
  mk_patt (pattern_desc patt)

and pattern_desc pat =
  begin match pat with
  | Owildpat -> Pany
  | Oconstpat(c) -> Pconst (immediate c)
  | Oconstr0pat(x) -> Pconstr (lident x, None)
  | Oconstr1pat(x, p) ->
      Pconstr (lident x, Some (ptuple (List.map pattern p)))
  | Ovarpat(n, _ty_exp) -> Pid (ident n)
  | Otuplepat(pat_list) -> Ptuple (List.map pattern pat_list)
  | Oaliaspat(_p, _n) -> not_yet_implemented "pat alias"
  | Oorpat(_pat1, _pat2) -> not_yet_implemented "or pat"
  | Otypeconstraintpat(_p, _ty_exp) -> not_yet_implemented "pat contraint"
  | Orecordpat(_n_pat_list) -> not_yet_implemented "record pat"
  end

(** [expression ctx state_vars e] translation of the expression [e] in
    a context [ctx] which returns the pair [(state_vars, e)]. The
    context [ctx] is the optional machine that contains the expression.
*)
let rec expression (ctx: _ option) state_vars e =
  mk_expr (expression_desc ctx state_vars e)

and expression_desc ctx state_vars e =
  begin match e with
  | Oconst c -> pack state_vars (Econst (immediate c))
  | Oconstr0(lname) ->
      pack state_vars (Econstr (lident lname, None))
  | Oconstr1(lname, e_list) ->
      let x_e_list = List.map (fun e -> (fresh "_x", e)) e_list in
      let args = etuple (List.map (fun (x, _) ->  evar x) x_e_list) in
      let k = pack state_vars (Econstr (lident lname, Some args)) in
      List.fold_left
        (fun k (x, e) ->
           Elet(unpack state_vars (pvar x),
                expression ctx state_vars e,
                mk_expr k))
        k x_e_list
  | Oglobal(ln) -> pack state_vars (Evar (lident ln))
  | Olocal(n) -> pack state_vars (Evar (ident n))
  | Ovar(_is_mutable, n) -> pack state_vars (Evar (ident n))
  | Ostate(l) -> pack state_vars (left_state_value l)
  | Oaccess(_e, _eidx) -> not_yet_implemented "expression: access"
  | Ovec(_e, _se) -> not_yet_implemented "expression: vec"
  | Oupdate(_se, _e1, _i, _e2) -> not_yet_implemented "expression: update"
  | Oslice(_e, _s1, _s2) -> not_yet_implemented "expression: slice"
  | Oconcat(_e1, _s1, _e2, _s2) -> not_yet_implemented "expression: concat"
  | Otuple(e_list) ->
      let x_e_list = List.map (fun e -> (fresh "_x", e)) e_list in
      let out = etuple_expr (List.map (fun (x, _) ->  Evar x) x_e_list) in
      let k = pack state_vars out in
      List.fold_left
        (fun k (x, e) ->
           Elet(unpack state_vars (pvar x),
                expression ctx state_vars e,
                mk_expr k))
        k x_e_list
  | Oapp(e, e_list) ->
      let x_e_list = List.map (fun e -> (fresh "_x", e)) e_list in
      let f = fresh "_f" in
      let out =
        List.fold_left (fun acc (x, _) -> Eapp (mk_expr acc, evar x))
          (Evar f) x_e_list in
      let k = pack state_vars out in
      List.fold_left
        (fun k (x, e) ->
           Elet(unpack state_vars (pvar x),
                expression ctx state_vars e,
                mk_expr k))
        k ((f, e) :: x_e_list)
  | Omethodcall m -> method_call ctx state_vars m
  | Orecord(r) ->
      let x_x'_e_list =
        List.map (fun (x,e) -> let x = lident x in (x, fresh ("_"^x.name), e)) r
      in
      let r = List.map (fun (x, x', _) ->  x, evar x') x_x'_e_list in
      let k = pack state_vars (Erecord(r, None)) in
      List.fold_left
        (fun k (_, x', e) ->
           Elet(unpack state_vars (pvar x'),
                expression ctx state_vars e,
                mk_expr k))
        k x_x'_e_list
  | Orecord_with(e_record, r) ->
      let x_x'_e_list =
        List.map (fun (x,e) -> let x = lident x in (x, fresh x.name, e)) r
      in
      let r = List.map (fun (x, x', _) ->  x, evar x') x_x'_e_list in
      let k =
        let x = fresh "_r" in
        Elet(unpack state_vars (pvar x),
                expression ctx state_vars e,
                mk_expr (pack state_vars (Erecord(r, Some (evar x)))))
      in
      List.fold_left
        (fun k (_, x', e) ->
           Elet(unpack state_vars (pvar x'),
                expression ctx state_vars e,
                mk_expr k))
        k x_x'_e_list
  | Orecord_access(e_record, lname) ->
      let x = fresh "_r" in
      let out = Efield (evar x, lident lname) in
      Elet(unpack state_vars (pvar x),
           expression ctx state_vars e,
           mk_expr (pack state_vars out))
  | Otypeconstraint(e, _ty_e) ->
      expression_desc ctx state_vars e
  | Oifthenelse(e, e1, e2) ->
      let b = fresh "_b" in
      let out =
        Eif (evar b, expression ctx state_vars e1,
             expression ctx state_vars e2)
      in
      Elet(unpack state_vars (pvar b),
           expression ctx state_vars e,
           mk_expr out)
  | Oinst(i) -> (instruction ctx state_vars i).expr
  end

and left_value left =
  begin match left with
  | Oleft_name x -> Evar (ident x)
  | Oleft_record_access (left, x) ->
      Efield(mk_expr (left_value left), lident x)
  | Oleft_index (_, _) -> not_yet_implemented "left_index update"
  end

and left_state_value left =
  match left with
  | Oself -> Evar self
  | Oleft_instance_name(n) -> Efield (self_expr, ident n)
  | Oleft_state_global(ln) -> Evar (lident ln)
  | Oleft_state_name(n) -> Efield (self_expr, ident n)
  | Oleft_state_record_access(left, n) ->
      Efield (mk_expr (left_state_value left), lident n)
  | Oleft_state_index(_left, _idx) ->
      not_yet_implemented "left_state_index"
  | Oleft_state_primitive_access(_left, _a) ->
      not_yet_implemented "primitive_access"

and method_call ctx state_vars m =
  begin match m.met_machine with
  | Some x when is_sample x || is_observe x || is_factor x ->
      begin match m.met_name with
      | "reset" -> pack state_vars eunit.expr
      | "copy" -> pack state_vars eunit.expr
      | "step" ->
          begin match m.met_args with
          | [ e ] when is_sample x ->
              begin match split_proba_expr e with
              | None -> assert false
              | Some (prob, e) ->
                  let state_vars' = IdSet.remove prob state_vars in
                  let x = fresh "_x" in
                  let d = fresh "_d" in
                  Elet (unpack state_vars' (ptuple [ pvar prob; pvar x ]),
                        mk_expr (Elet (unpack state_vars (pvar d),
                                       expression ctx state_vars e,
                                       mk_expr
                                         (pack state_vars'
                                            (Esample(prob.name, evar d))))),
                        mk_expr (pack state_vars (evar x).expr))
              end
          | [ e ] when is_observe x ->
              begin match split_proba_expr e with
              | None -> assert false
              | Some (prob, e) ->
                  let state_vars' = IdSet.remove prob state_vars in
                  let x = fresh "_x" in
                  let d = fresh "_d" in
                  let o = fresh "_o" in
                  Elet(unpack state_vars' (ptuple [pvar prob; pvar x]),
                       mk_expr
                         (Elet (unpack state_vars (ptuple [ pvar d; pvar o]),
                                expression ctx state_vars e,
                                mk_expr
                                  (pack state_vars'
                                     (Eobserve(prob.name, evar d, evar o))))),
                       mk_expr (pack state_vars (evar x).expr))
              end
          | [ e ] when is_factor x ->
              begin match split_proba_expr e with
              | None -> assert false
              | Some (prob, e) ->
                  let state_vars' = IdSet.remove prob state_vars in
                  let x = fresh "_x" in
                  let f = fresh "_f" in
                  Elet(unpack state_vars' (ptuple [pvar prob; pvar x]),
                       mk_expr
                         (Elet (unpack state_vars (pvar f),
                                expression ctx state_vars e,
                                mk_expr
                                  (pack state_vars'
                                     (Efactor(prob.name, evar f))))),
                       mk_expr (pack state_vars (evar x).expr))
              end
          | _ -> assert false
          end
      | _ -> assert false
      end
  | _ -> standard_method_call ctx state_vars m
  end

and standard_method_call ctx state_vars m =
  let instance =
    match m.met_instance with
    | None -> self_expr
    | Some (i, []) -> mk_expr (Efield (self_expr, ident i))
    | Some (i, _) -> not_yet_implemented "instance array"
  in
  let o_prob, args =
    match split_proba_expr (Otuple m.met_args) with
    | None -> None, Otuple m.met_args
    | Some (prob, args) -> Some prob, args
  in
  let args_var = fresh "_args" in
  let call =
    match m.met_name with
    | "reset" -> Ecall_reset instance
    | "step" ->
        let args' =
          match o_prob with
          | None -> evar args_var
          | Some prob -> etuple [evar prob; evar args_var]
        in
        Ecall_step (instance, args')
    | "copy" -> not_yet_implemented "copy"
    | _ -> assert false
  in
  let call =
    match m.met_instance with
    | None -> call
    | Some (i, []) ->
        let state = fresh ("_" ^ self.name ^ "_" ^ (ident i).name) in
        let res = fresh ("_res_" ^ (ident i).name) in
        let self_update =
          mk_expr (Erecord ([ident i, evar state], Some self_expr))
        in
        Elet (ptuple [pvar state; pvar res],
              mk_expr call,
              etuple [self_update; evar res])
    | Some (i, _) -> not_yet_implemented "instance array"
  in
  let state_vars_args = fv_expr_updated args in
  assert (IdSet.subset state_vars_args state_vars);
  match o_prob with
  | None ->
      let res = fresh "_res" in
      Elet(unpack state_vars_args (pvar args_var),
           expression ctx state_vars_args args,
           mk_expr
             (Elet (ptuple [ self_patt; pvar res ],
                    mk_expr call,
                    mk_expr (pack state_vars (evar res).expr))))
  | Some prob ->
      let res = fresh "_res" in
      Elet(unpack state_vars_args (pvar args_var),
           expression ctx state_vars_args args,
           mk_expr
             (Elet (ptuple [ self_patt; ptuple [ pvar prob; pvar res ]],
                    mk_expr call,
                    mk_expr (pack state_vars (evar res).expr))))

and instruction ctx state_vars i =
  inst ctx state_vars (add_return i)

and inst ctx state_vars i =
  let e = inst_desc ctx state_vars i in
  mk_expr e

and inst_desc ctx state_vars i =
  begin match i with
  | Olet(p, e, i) ->
      let p = pattern p in
      assert (IdSet.disjoint (fv_patt p) state_vars);
      let state_vars' = fv_expr_updated e in
      Elet (unpack state_vars' p, expression ctx state_vars' e,
            inst ctx state_vars i)
  | Oletvar(x, _is_mutable, ty, e_opt, i) ->
      let ty = type_expr_of_typ ty in
      let p = pattern (Ovarpat(x, ty)) in
      assert (IdSet.disjoint (fv_patt p) state_vars);
      let e = Option.value ~default:(Oconst Oany) e_opt in
      let state_vars_e = fv_expr_updated e in
      let state_vars_i = IdSet.add (ident x) state_vars in
      let o = fresh "_o" in
      Elet (unpack state_vars_i (pvar o),
            mk_expr
              (Elet (unpack state_vars_e p, expression ctx state_vars_e e,
                     inst ctx state_vars_i i)),
            mk_expr (pack state_vars (evar o).expr))
  | Ofor(_is_to, _n, _e1, _e2, _i3) -> not_yet_implemented "for"
  | Owhile(_e1, _i2) -> not_yet_implemented "while"
  | Oassign(left, e) ->
      let updated = fv_expr_updated e in
      assert (IdSet.subset updated state_vars);
      let left_var = var_of_left_value left in
      Elet (unpack (IdSet.remove left_var updated) (pvar left_var),
            left_value_update ctx updated left_var left e,
            mk_expr (pack state_vars eunit.expr))
  | Oassign_state(left, e) ->
      let updated = fv_expr_updated e in
      assert (IdSet.subset updated state_vars);
      let left_var = var_of_left_state_value left in
      Elet (unpack (IdSet.remove left_var updated) (pvar left_var),
            left_state_value_update ctx updated left_var left e,
            mk_expr (pack state_vars eunit.expr))
  | Osequence l ->
      begin match List.rev l with
      | [] -> eunit.expr
      | i :: rev_l ->
          List.fold_left
            (fun k i ->
              let state_vars' = fv_updated i in
              assert (IdSet.subset state_vars' state_vars);
              Elet (unpack state_vars' pany, inst ctx state_vars' i, mk_expr k))
            (inst_desc ctx state_vars i) rev_l
      end
  | Oexp(e) -> expression_desc ctx state_vars e
  | Oif(e, i1, o_i2) ->
      let i2 = Option.value ~default:(Oexp(Oconst Ovoid)) o_i2 in
      let updated_e = fv_expr_updated e in
      let updated_i =
        IdSet.union updated_e (IdSet.union (fv_updated i1) (fv_updated i2))
      in
      assert (IdSet.subset updated_i state_vars);
      let b = fresh "_b" in
      let res = fresh "_res_if" in
      Elet (unpack updated_e (pvar b),
            expression ctx updated_e e,
            mk_expr (Elet (unpack updated_i (pvar res),
                           mk_expr (Eif (evar b,
                                         inst ctx updated_i i1,
                                         inst ctx updated_i i2)),
                           mk_expr (pack state_vars (evar res).expr))))
  | Omatch(e, match_handler_l) ->
      let updated_e = fv_expr_updated e in
      let updated_i =
        List.fold_left
          (fun acc hdl -> IdSet.union acc (fv_updated hdl.w_body))
          updated_e match_handler_l
      in
      assert (IdSet.subset updated_i state_vars);
      let match_ =
        let x = fresh "_x" in
        Elet (unpack updated_e (pvar x),
              expression ctx updated_e e,
              mk_expr
                (Ematch (evar x,
                         List.map
                           (fun hdl ->
                             { case_patt = pattern hdl.w_pat;
                               case_expr = inst ctx updated_i hdl.w_body})
                           match_handler_l)))
      in
      let res = fresh "_res_match" in
      Elet (unpack updated_i (pvar res), mk_expr match_,
            mk_expr (pack state_vars (evar res).expr))
  end

and type_expr_of_typ =
  let cpt = ref 0 in
  fun _ty ->
    incr cpt;
    Otypevar ("'a"^(string_of_int !cpt))

and left_value_update ctx state_vars left_var left e =
  begin match left with
  | Oleft_name _ -> expression ctx state_vars e
  | Oleft_record_access (left, x) ->
      let tmp = fresh "_tmp" in
      mk_expr (Elet (unpack state_vars (pvar tmp),
                     expression ctx state_vars e,
                     mk_expr (pack (IdSet.remove left_var state_vars)
                                (Erecord([lident x, evar tmp],
                                         Some (mk_expr (left_value left)))))))
  | Oleft_index (_, _) -> not_yet_implemented "left_index update"
  end

and left_state_value_update ctx state_vars left_var left e =
  begin match left with
  | Oself -> expression ctx state_vars e
  | Oleft_instance_name x ->
      let tmp = fresh "_tmp" in
      mk_expr (Elet (unpack state_vars (pvar tmp),
                     expression ctx state_vars e,
                     mk_expr (pack (IdSet.remove left_var state_vars)
                                (Erecord([ident x, evar tmp],
                                         Some self_expr)))))
  | Oleft_state_global _ln -> expression ctx state_vars e
  | Oleft_state_name n ->
      let tmp = fresh "_tmp" in
      mk_expr (Elet (unpack state_vars (pvar tmp),
                     expression ctx state_vars e,
                     mk_expr (pack (IdSet.remove left_var state_vars)
                                (Erecord([ident n, evar tmp],
                                         Some self_expr)))))
  | Oleft_state_record_access(left, n) ->
      let tmp = fresh "_tmp" in
      mk_expr (Elet (unpack state_vars (pvar tmp),
                     expression ctx state_vars e,
                     mk_expr (pack (IdSet.remove left_var state_vars)
                                (Erecord([lident n, evar tmp],
                                         Some (mk_expr (left_state_value left)))))))
  | Oleft_state_index(_left, _idx) ->
      not_yet_implemented "left_state_index update"
  | Oleft_state_primitive_access(_left, _a) ->
      not_yet_implemented "primitive_access update"
  end

and add_return i =
  begin match i with
  | Olet(p, e, i) -> Olet(p, e, add_return i)
  | Oletvar(x, is_mutable, ty, e_opt, i) ->
      Oletvar(x, is_mutable, ty, e_opt, add_return i)
  | Ofor(is_to, n, e1, e2, i3) ->
      Osequence [ Ofor(is_to, n, e1, e2, add_return i3);
                  Oexp (Oconst (Ovoid)) ]
  | Owhile(e1, i2) -> Osequence [ Owhile(e1, add_return i2);
                                  Oexp (Oconst (Ovoid)) ]
  | Oassign(left, e) -> Osequence [ Oassign(left, e); Oexp (Oconst (Ovoid)) ]
  | Oassign_state(left, e) ->
      Osequence [ Oassign_state(left, e); Oexp (Oconst (Ovoid)) ]
  | Osequence l ->
      begin match l with
      | [] -> Oexp (Oconst (Ovoid))
      | [ i ] -> add_return i
      | _ -> Osequence (List.map add_return l)
      end
  | Oexp(e) -> Oexp(e)
  | Oif(e, i1, oi2) ->
      Oif(e, add_return i1, Option.map add_return oi2)
  | Omatch(e, match_handler_l) ->
      Omatch (e, List.map
                (fun hdl -> { hdl with w_body = add_return hdl.w_body })
                match_handler_l)
  end

let machine_type memories instances =
  let i, params, entries =
    List.fold_right
      (fun { m_name = n } (i, params, entries) ->
         let m = Zmisc.int_to_alpha i in
         (i+1, m :: params, ((ident n).name, Tvar m) :: entries))
      memories (0, [], [])
  in
  let i, params, entries =
    List.fold_right
      (fun { i_name = n } (i, params, entries) ->
         let m = Zmisc.int_to_alpha i in
         (i+1, m :: params, ((ident n).name, Tvar m) :: entries))
      instances (i, params, entries)
  in
  (params, TKrecord entries)

let machine_init ma m_reset =
  let i_opt = ma.ma_initialize in
  let memories = ma.ma_memories in
  let instances = ma.ma_instances in
  let memory { m_name = n; m_value = e_opt;
	       m_typ = _ty; m_kind = k_opt; m_size = m_size } =
    begin match k_opt with
    | None ->
       (* discrete state variable *)
        if m_size <> [] then not_yet_implemented "array in memory";
        let e = Option.value ~default:(Oconst Oany) e_opt in
        let state_vars = fv_expr_updated e in
        (ident n, expression None state_vars e)
    | Some _ -> not_yet_implemented "non discrete memory"
    end
  in
  let instance { i_name = n; i_machine = ei;
		 i_kind = _k; i_params = e_list; i_size = ie_size } =
    if ie_size <> [] then not_yet_implemented "array on instances";
    if e_list <> [] then assert false;
    begin match ei with
    | Oglobal x when is_sample x || is_observe x || is_factor x ->
        (ident n, eunit)
    | Oapp (Oglobal infer, nb :: f :: args) when get_id infer = "infer" ->
        let f_init =
          match f with
          | Oglobal x -> lident x
          | Olocal x  | Ovar (_, x) -> ident x
          | _ -> assert false
        in
        (ident n, einfer_init (expression None IdSet.empty nb) f_init)
    | Oglobal x ->
        (ident n, instance_init (lident x))
    | Olocal x  | Ovar (_, x) ->
        (ident n, instance_init (ident x))
    | Oapp (Oglobal f, args) ->
        let f = evar (lident f) in
        let args = List.map (expression None IdSet.empty) args in
        let tmp = fresh "_tmp" in
        let instance =
          mk_expr (Elet (pvar tmp,
                         List.fold_left
                           (fun acc arg -> mk_expr (Eapp (acc, arg)))
                           f args,
                         instance_init tmp))
        in
        (ident n,  instance)
    | _ -> assert false
    end
  in
  let r =
    mk_expr
      (Erecord
         ((List.map memory memories) @ (List.map instance instances), None))
  in
  let alloc =
    match i_opt with
    | None -> r
    | Some i ->
        let state_vars = fv_updated i in
        mk_expr (Elet(unpack state_vars pany, instruction None state_vars i, r))
  in
  let sself = fv_updated m_reset.me_body in
  let reset = instruction (Some ma) sself m_reset.me_body in
  mk_expr (Elet (self_patt, alloc,
                 mk_expr (Elet (unpack sself pany, reset, self_expr))))

let machine_method ma { me_name = me_name; me_params = pat_list;
                                    me_body = i; me_typ = _ty } =
  let state_vars = IdSet.singleton self in
  begin match split_proba_patt pat_list with
  | None ->
      assert (IdSet.subset (fv_updated i) state_vars);
      let args = ptuple [ self_patt; (ptuple (List.map pattern pat_list)) ] in
      let body = instruction (Some ma) state_vars i in
      args, body
  | Some (prob, pat_list) ->
      let state_vars = IdSet.add prob state_vars in
      assert (IdSet.subset (fv_updated i) state_vars);
      let args =
        ptuple [ self_patt;
                 ptuple (pvar prob :: List.map pattern pat_list) ] in
      let o = fresh "_o" in
      let body =
        mk_expr (Elet (unpack state_vars (pvar o),
                       instruction (Some ma) state_vars i,
                       etuple [ self_expr;
                                etuple [ evar prob; evar o ] ]))
      in
      (args, body)
  end

let machine name m =
  let m_step = List.find (fun me -> me.me_name = Oaux.step) m.ma_methods in
  let m_reset = List.find (fun me -> me.me_name = Oaux.reset) m.ma_methods in
  let params = List.map pattern m.ma_params in
  let node =
    { n_type = machine_type m.ma_memories m.ma_instances;
      n_init = machine_init m m_reset;
      n_step = machine_method m m_step; }
  in
  mk_decl (Dnode (name, params, node))


let type_decl tdecl =
  match tdecl with
  | Oabstract_type -> TKabstract_type
  | Oabbrev t -> TKabbrev (type_expression t)
  | Ovariant_type l ->
      TKvariant_type
        (List.map
           (function
             | Oconstr0decl x -> (x, None)
             | Oconstr1decl (x, l) -> (x, Some (List.map type_expression l)))
           l)
  | Orecord_type l ->
      TKrecord (List.map (fun (x,t) -> (x, type_expression t)) l)

let implementation impl =
  begin match impl with
  | Oletvalue (x, i) ->
      [ mk_decl (Ddecl (pvar {modul = None; name = x},
                        instruction None (fv_updated i) i)) ]
  | Oletfun (f, args, i) ->
      let args =
        begin match args with
        | [] -> mk_patt Pany
        | [p] -> pattern p
        | _ -> mk_patt (Ptuple (List.map pattern args))
        end
      in
     [ mk_decl (Dfun (f, args, instruction None (fv_updated i) i)) ]
  | Oletmachine (x, m) ->
      [ machine x m ]
  | Oopen m ->
      [ mk_decl (Dopen m) ]
  | Otypedecl l ->
      [ mk_decl (Dtype
                   (List.map
                      (fun (t, args, decl) ->
                        (t, args, type_decl decl))
                      l)) ]
  end

let rewrite_decl f d =
  let rec rewrite_decl n f d =
    let d' = map_decl_desc (fun p -> p) f d in
    if d = d' || n < 0 then d
    else rewrite_decl (n - 1) f d'
  in
  rewrite_decl 10000 f d

let simplify d =
  let r_expr expr =
    let expr = Muf_rewrites.simplify_lets expr in
    let expr = Muf_rewrites.simplify_ignore expr in
    let expr = Muf_rewrites.constant_propagation expr in
    let expr = Muf_rewrites.single_and_no_use expr in
    let expr = Muf_rewrites.merge_record_update expr in
    let expr = Muf_rewrites.simplify_record_access expr in
    expr
  in
  { decl = rewrite_decl r_expr d.decl }

let implementation_list l =
  let l = List.map implementation l in
  let l = List.map (List.map simplify) l in
  l