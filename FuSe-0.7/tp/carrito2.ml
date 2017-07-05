(*
	Tipos:
	catalogo es una lista de 3-upla  ((id,cant),precio)
	carrito y pedido son listas de 2-uplas id,cant
	producto es una 2-upla id,cant
 *)

module S = Session.Bare

let print_list f lst =
  let rec print_elements = function
    | [] -> ()
    | (a,b)::t -> print_string "("; f a; print_string ","; f b; print_string ")"; print_string ";"; print_elements t
  in
  print_string "[";
  print_elements lst;
  print_string "]";;

let rec aux_catalogo i n catalogo =
	Random.init(n);
	if i < n then
	let a = ((i, (Random.int n) +1), (Random.int n) +1) in
	a :: aux_catalogo (i+1) n catalogo
 	else []

let crear_catalogo n =
	aux_catalogo 0 n []

let rec find2 lista elem =
	match lista with
	| [] -> ((-1,-1),-1)
	| ((a,b),c) :: xs -> if a = elem then ((a,b),c) else find2 xs elem

(* auxiliares de pedido *)
let rec verif_pedido catalogo pedido =
	match pedido with
    | [] -> true
    | (id, cant) :: xs -> let ((_,b),_) = find2 catalogo id in
    						if b  >= cant then (* List.find (s -> cond) catalogo devuelve el elemento s en la lista catalogo si lo encuentra *)
    						verif_pedido catalogo xs else false

let rec devolver_disponibles catalogo pedido =
	match pedido with
	| [] -> []
	| (id, _) :: xs -> let ((_,b),_) = find2 catalogo id in
							(id, b) :: devolver_disponibles catalogo xs

let rec sumar_en_carrito carrito pedido =
	match carrito with
	| [] ->
		(match pedido with
		| [] -> []
		| y :: ys -> y :: sumar_en_carrito [] ys)

	| (id,cant) :: xs ->
		(match pedido with
		| [] -> (id, cant) :: sumar_en_carrito xs []
		| (id2, cant2) :: ys -> if id = id2 then (id, cant + cant2) :: sumar_en_carrito xs  ys	(* asumo ambas listas ordenadas, sino no funca ni a palos *)
			else if id < id2 then (id, cant2) :: sumar_en_carrito xs pedido
			else (id, cant2) :: sumar_en_carrito carrito ys)

let rec restar_en_catalogo catalogo pedido =
	match catalogo with
	| [] -> []
	| ((id, cant), precio) :: xs ->
		match pedido with
		| [] -> ((id, cant), precio) :: restar_en_catalogo xs pedido
		| (id2, cant2) :: ys -> if id = id2 then
			let a = ((id, cant - cant2), precio) in
			a :: restar_en_catalogo xs  ys	(* asumo ambas listas ordenadas, sino no funca ni a palos *)
			else
				((id, cant2), precio) :: restar_en_catalogo xs pedido
(* auxiliar de solicitar *)
let rec solicitar catalogo carrito =
	match carrito with
	| [] -> 0
	| (id, cant) :: xs -> let (_,c) = find2 catalogo id in
							cant*c + solicitar catalogo xs

(* auxiliar de avandonar*)
let rec anular_carrito catalogo carrito =
	match catalogo with
	| [] -> []
	| ((id, cant), _) :: xs ->
		match carrito with
		| [] -> (id, cant) :: anular_carrito xs carrito
		| (id2, cant2) :: ys -> if id = id2 then (id, cant + cant2) :: anular_carrito xs  ys	(* asumo ambas listas ordenadas, sino no funca ni a palos *)
			else
				(id, cant2) :: anular_carrito xs carrito

(* auxiliares de quitar *)
let rec quitar_carrito carrito producto =
	match carrito with
	| [] -> []
	| (id, cant) :: xs -> let (a,b) = producto in
							if a = id then
								if b < cant then (id, cant - b) :: quitar_carrito xs producto
								else quitar_carrito xs producto
							else (id, cant) :: quitar_carrito xs producto

let rec diferencia carrito producto =
	match carrito with
	| [] -> 0
	| (id, cant) :: xs -> let (a,b) = producto in
							if a = id then
								if b < cant then b
								else cant
							else diferencia xs producto

let rec devolver_a_catalogo catalogo carrito producto =
	match catalogo with
	| [] -> []
	| ((id, cant), precio) :: xs -> let (a,_) = producto in
							if a = id then
								let d = diferencia carrito producto in
								((id, cant + d),precio) :: devolver_a_catalogo xs carrito producto
							else
								((id, cant),precio) :: devolver_a_catalogo xs carrito producto
(* auxiliares de finalizar 
let rec cobrar catalogo carrito =
	match carrito with
    | [] -> true
    | (id, cant) :: xs -> let ((_,b),_) = find2 catalogo id in
    						if b  >= cant then
    						cobrar catalogo xs else false
*)



(* FUNCIONES PRINCIPALES *)
let rec server s =
 	match S.branch s with
  	(* Recibimos catalogo, carrito y pedido. Verificamos que las cantidades del pedido puedan satisfacerse, agregamos esas cantidades al carrito y
  	las quitamos del catalogo. Sino, devolvemos la lista de los elementos del pedido con las cant del catalogo *)
  	| `Pedir s -> let n, s = S.receive s in
	       let m, s = S.receive s in
	       let p, s = S.receive s in
	       let r = verif_pedido n p in
	       let s = S.send r s in
	       if r = false then
		       let s = S.send n s in
		       (*let s = S.send m s in *)
		       let s = S.send (devolver_disponibles n p) s in (* devuelvo el catalogo, carrito y la respuesta al pedido erroneo *)
		       (* enviar s a client() *)
		       server s
		   else
		   		let t = restar_en_catalogo n p in
		   		let s = S.send t s in (* devuelvo el catalogo modificado y el carrito modificado *)
		        let s = S.send (sumar_en_carrito m p) s in
		       (* enviar s a client() *)
		       server s

	(* Solicitar multiplica cant * precio para cada elemento del carrito *)
	| `Solicitar s -> let n, s = S.receive s in
	       let m, s = S.receive s in
	       let r = (solicitar n m) in
	       print_list print_int m;
	       print_int r;
	       server s

	(*la idea es agarrar la lista del carrito y volcarla en el catalogo  *)
  	| `Abandonar s -> let n, s = S.receive s in
	       let m, s = S.receive s in
	       let s = S.send (anular_carrito n m) s in 	(* devuelvo el catalogo completo. Y el carrito vacio?*)
	       S.close s

	(* quita el elemento pedido del carrito. Si se quieren quitar mas o los mismos elementos que hay, se quita el item *)
	| `Quitar s -> let n, s = S.receive s in
	       let m, s = S.receive s in
	       let q, s = S.receive s in
	       let s = S.send (devolver_a_catalogo n m q) s in
	       let s = S.send (quitar_carrito m q) s in
	       (* enviar s a client() *)
		    server s

	| `Finalizar1 s ->
	let n, s = S.receive s in
	let m, s = S.receive s in
	 	let r = Random.bool () in
	       	if r = true then
	      	    	let s = S.select (fun x -> `Salir x) s in
	      	    	S.close s
		    else
			let s = S.select (fun x -> `Fallo x) s in
			let s = S.send (-1) s in
			server s

(*	| `Fallo s -> let s = S.send (-1) s in
	      	    	server s
*)
(*	| `Salir  s ->  (* let n, s = S.receive s in
	       		let m, s = S.receive s in
			let s = S.send (solicitar n m) s in *)
			S.close s
*)

(* aca simulamos el cliente, y hacemos q llame al servidor con los distintos datos "hardcodeados". Como si el cliente lo recibiera de la persona. *)
let client s =
	print_newline();
	print_string "1";
	print_newline();




	let s = S.select (fun x -> `Pedir x) s in (* select `Pedir operation *)
	let s = S.send (crear_catalogo 10) s in
	let s = S.send [] s in
	(*let pedido = [(2,4);(4,3);(5,1)] in*)
(* para el c) enviamos el pedido vacío directamente, notar que para que esto funcione, se debe comentar casi todo el código, no se debe hacer solicitar ni quitar*)
	let pedido = [] in
	let s = S.send pedido s in

	print_string "2";
	print_newline();
	let ok, s = S.receive s in
	Printf.printf "%B" ok;
	print_newline();
	let cat, s = S.receive s in
	let carr, s = S.receive s in

	print_string "3";
	print_newline();

(* aca comenzaría el bloque que hay que comentar del c) *)
(* para el d) hay que enviar el carrito vacio como en el punto c) y comentar a partir de la linea indicada mas abajo *)
	let cat = (crear_catalogo 10) in
	let carr = [] in


	let s = S.select (fun x -> `Quitar x) s in (* select `Quitar operation *)
	let s = S.send cat s in
	let s = S.send carr s in
	let quitar = (5,7) in
	let s = S.send quitar s in

	print_string "4";
	print_newline();
	let cat, s = S.receive s in
	let carr, s = S.receive s in
	print_string "5";
	print_newline();
(*para el punto d) hay que comentar la parte de solicitar para ver que efectivamente se puede eliminar un objeto que no esta en una lista vacia *)
(*	let s = S.select (fun x -> `Solicitar x) s in (* select `Solicitar operation *)
	let s = S.send cat s in
	let s = S.send carr s in*)
(* para el a) agregamos un nuevo paso en el cliente, hace todo y primero sale y luego intenta finalizar 
	print_string "6";
	print_newline();
	let s = S.select (fun x -> `Salir x) s in (* select `salir operation *)

SI SE DESCOMENTA este bloque, se puede ver que no compila el programa, así que a) es imposible
*)



(* y aca terminaría el bloque de c), se puede ver que se puede comprar un carrito vacío sin ningún problema.*)
	print_string "7";
	print_newline();
	let s = S.select (fun x -> `Finalizar1 x) s in (* select `Finalizar1 operation *)
	let s = S.send cat s in
	let s = S.send carr s in

(* para el b) intentamos pedir luego de finalizar

	let s = S.select (fun x -> `Pedir x) s in (* select `Pedir operation *)
	let s = S.send (crear_catalogo 10) s in
	let s = S.send [] s in
	let pedido2 = [(2,4);(4,3);(5,1)] in
	let s = S.send pedido2 s in

Si se descomenta este bloque, se puede ver que el código no compila, así que b) también es imposible.

*)


	print_string "8";

   	match S.branch s with
	    `Fallo s ->
			let _,s = S.receive s in
			let s = S.select (fun x-> `Abandonar x) s in
			let s = S.send cat s in
			let s = S.send carr s in
			let _,s = S.receive s in
							S.close s
			| `Salir s -> S.close s


 let _ =
	print_string "0";
  	let a, b = S.create () in
	let _ = Thread.create server a in
 	client b
 
