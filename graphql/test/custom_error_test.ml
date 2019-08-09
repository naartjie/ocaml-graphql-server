open Test_common

module Err = struct
  type t = | String of string | Extension of string * string
  let message_of_error t = match t with
    | String s -> s
    | Extension _ -> ""
  let extensions_of_error t = match t with
    | String _ -> []
    | Extension (k, v) -> [(k, `String v)]
end

module CustomErrorsSchema = Graphql_schema.Make (struct
  type +'a t = 'a

  let bind t f = f t
  let return t = t

  module Stream = struct
    type 'a t = 'a Seq.t

    let map t f = Seq.map f t
    let iter t f = Seq.iter f t
    let close _t = ()
  end
end) (Err)

let test_query schema ctx ?variables ?operation_name query expected =
  match Graphql_parser.parse query with
  | Error err -> failwith err
  | Ok doc ->
      let result = match CustomErrorsSchema.execute schema ctx ?variables ?operation_name doc with
      | Ok (`Response data) -> data
      | Ok (`Stream stream) ->
          begin try match stream () with
          | Seq.Cons (Ok _, _) -> `List (list_of_seq stream)
          | Seq.Cons (Error err, _) -> err
          | Seq.Nil -> `Null
          with _ -> `String "caught stream exn" end
      | Error err -> err
      in
      Alcotest.check yojson "invalid execution result" expected result

let schema = CustomErrorsSchema.(schema [
  io_field "string_error"
    ~typ:int
    ~args:Arg.[]
    ~resolve:(fun _ () -> Error (Err.String "error string"));
  io_field "extensions_error"
    ~typ:int
    ~args:Arg.[]
    ~resolve:(fun _ () -> Error (Err.Extension ("custom", "json")))
])

let suite = [
  ("message without extensions", `Quick, fun () ->
    let query = "{ string_error }" in
    test_query schema () query (`Assoc [
      "errors", `List [
        `Assoc [
          "message", `String "error string";
          "path", `List [`String "string_error"]
        ]
      ];
      "data", `Assoc [
        "string_error", `Null
      ]
    ])
  );
  ("message with extensions", `Quick, fun () ->
    let query = "{ extensions_error }" in
    test_query schema () query (`Assoc [
      "errors", `List [
        `Assoc [
          "message", `String "";
          "path", `List [`String "extensions_error"];
          "extensions", `Assoc [
            "custom", `String "json"
          ]
        ]
      ];
      "data", `Assoc [
        "extensions_error", `Null
      ]
    ])
  );
]
