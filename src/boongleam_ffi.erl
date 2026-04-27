-module(boongleam_ffi).
-export([copy_file/2, exit/1, get_env/1, http_request/3, is_directory/1,
         list_files_recursive/1, make_dir_all/1, monotonic_microsecond/0, otp_release/0,
         read_text_file/1, runtime_summary/0, sha256_hex/1, start_arguments/0,
         websocket_smoke/4, write_text_file/2]).

start_arguments() ->
    [unicode:characters_to_binary(Arg) || Arg <- init:get_plain_arguments()].

read_text_file(Path) ->
    case file:read_file(binary_to_list(Path)) of
        {ok, Contents} ->
            {ok, Contents};
        {error, Reason} ->
            {error, unicode:characters_to_binary(file:format_error(Reason))}
    end.

is_directory(Path) ->
    filelib:is_dir(binary_to_list(Path)).

list_files_recursive(Path) ->
    Root = binary_to_list(Path),
    case filelib:is_dir(Root) of
        true ->
            Files = lists:sort(list_files_recursive_loop(Root)),
            {ok, [unicode:characters_to_binary(File) || File <- Files]};
        false ->
            {error, <<"directory does not exist">>}
    end.

list_files_recursive_loop(Directory) ->
    case file:list_dir(Directory) of
        {ok, Entries} ->
            lists:flatmap(
              fun(Entry) ->
                      Path = filename:join(Directory, Entry),
                      case filelib:is_dir(Path) of
                          true -> list_files_recursive_loop(Path);
                          false -> [Path]
                      end
              end,
              Entries
            );
        {error, _Reason} ->
            []
    end.

make_dir_all(Path) ->
    case filelib:ensure_dir(filename:join(binary_to_list(Path), ".keep")) of
        ok ->
            {ok, nil};
        {error, Reason} ->
            {error, unicode:characters_to_binary(file:format_error(Reason))}
    end.

write_text_file(Path, Contents) ->
    ListPath = binary_to_list(Path),
    case filelib:ensure_dir(ListPath) of
        ok ->
            case file:write_file(ListPath, Contents) of
                ok ->
                    {ok, nil};
                {error, Reason} ->
                    {error, unicode:characters_to_binary(file:format_error(Reason))}
            end;
        {error, Reason} ->
            {error, unicode:characters_to_binary(file:format_error(Reason))}
    end.

copy_file(Source, Destination) ->
    SourcePath = binary_to_list(Source),
    DestinationPath = binary_to_list(Destination),
    case filelib:ensure_dir(DestinationPath) of
        ok ->
            case file:copy(SourcePath, DestinationPath) of
                {ok, _BytesCopied} ->
                    {ok, nil};
                {error, Reason} ->
                    {error, unicode:characters_to_binary(file:format_error(Reason))}
            end;
        {error, Reason} ->
            {error, unicode:characters_to_binary(file:format_error(Reason))}
    end.

http_request(Method, Url, Body) ->
    application:ensure_all_started(inets),
    MethodAtom = list_to_atom(string:lowercase(binary_to_list(Method))),
    UrlString = binary_to_list(Url),
    Request = case MethodAtom of
        get ->
            {UrlString, []};
        post ->
            {UrlString, [], "application/json", binary_to_list(Body)};
        _ ->
            {UrlString, []}
    end,
    case httpc:request(MethodAtom, Request, [{timeout, 5000}], []) of
        {ok, {{_, Status, _}, _Headers, ResponseBody}} ->
            {ok, {Status, unicode:characters_to_binary(ResponseBody)}};
        {error, Reason} ->
            {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

websocket_smoke(Host, Port, Path, Messages) ->
    HostString = binary_to_list(Host),
    PathString = binary_to_list(Path),
    case gen_tcp:connect(HostString, Port, [binary, {active, false}, {packet, raw}], 5000) of
        {ok, Socket} ->
            try websocket_smoke_connected(Socket, HostString, Port, PathString, Messages) of
                Result -> Result
            after
                gen_tcp:close(Socket)
            end;
        {error, Reason} ->
            {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

websocket_smoke_connected(Socket, Host, Port, Path, Messages) ->
    Key = base64:encode(crypto:strong_rand_bytes(16)),
    Request = [
        "GET ", Path, " HTTP/1.1\r\n",
        "Host: ", Host, ":", integer_to_list(Port), "\r\n",
        "Upgrade: websocket\r\n",
        "Connection: Upgrade\r\n",
        "Sec-WebSocket-Key: ", Key, "\r\n",
        "Sec-WebSocket-Version: 13\r\n\r\n"
    ],
    case gen_tcp:send(Socket, iolist_to_binary(Request)) of
        ok ->
            case recv_http_upgrade(Socket, <<>>) of
                ok -> websocket_send_messages(Socket, Messages, []);
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} ->
            {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

recv_http_upgrade(Socket, Acc) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, Data} ->
            Next = <<Acc/binary, Data/binary>>,
            case binary:match(Next, <<"\r\n\r\n">>) of
                nomatch -> recv_http_upgrade(Socket, Next);
                _ ->
                    case binary:match(Next, <<" 101 ">>) of
                        nomatch -> {error, <<"websocket upgrade did not return 101">>};
                        _ -> ok
                    end
            end;
        {error, Reason} ->
            {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

websocket_send_messages(Socket, Messages, Acc) ->
    case Messages of
        [] ->
            {ok, lists:reverse(Acc)};
        [Message | Rest] ->
            case gen_tcp:send(Socket, encode_client_text_frame(Message)) of
                ok ->
                    case recv_text_frames(Socket, []) of
                        {ok, Frames} ->
                            websocket_send_messages(Socket, Rest, lists:reverse(Frames) ++ Acc);
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
            end
    end.

encode_client_text_frame(Payload) ->
    PayloadSize = byte_size(Payload),
    Mask = crypto:strong_rand_bytes(4),
    Header = case PayloadSize of
        N when N < 126 ->
            <<16#81, (16#80 bor N)>>;
        N when N < 65536 ->
            <<16#81, (16#80 bor 126), N:16/big>>;
        N ->
            <<16#81, (16#80 bor 127), N:64/big>>
    end,
    <<Header/binary, Mask/binary, (mask_payload(Payload, Mask))/binary>>.

mask_payload(Payload, Mask) ->
    mask_payload(Payload, Mask, 0, <<>>).

mask_payload(<<>>, _Mask, _Index, Acc) ->
    Acc;
mask_payload(<<Byte, Rest/binary>>, Mask, Index, Acc) ->
    MaskByte = binary:at(Mask, Index rem 4),
    mask_payload(Rest, Mask, Index + 1, <<Acc/binary, (Byte bxor MaskByte)>>).

recv_text_frames(Socket, Acc) ->
    Timeout = case Acc of
        [] -> 5000;
        _ -> 50
    end,
    case gen_tcp:recv(Socket, 2, Timeout) of
        {ok, <<16#81, LengthByte>>} ->
            Length0 = LengthByte band 16#7f,
            case recv_payload_length(Socket, Length0) of
                {ok, Length} ->
                    case gen_tcp:recv(Socket, Length, 5000) of
                        {ok, Payload} ->
                            recv_text_frames(Socket, [Payload | Acc]);
                        {error, Reason} ->
                            {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, <<16#88, _LengthByte>>} ->
            {ok, lists:reverse(Acc)};
        {error, timeout} ->
            case Acc of
                [] -> {error, <<"websocket frame receive timed out">>};
                _ -> {ok, lists:reverse(Acc)}
            end;
        {error, Reason} ->
            {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

recv_payload_length(Socket, Length0) ->
    case Length0 of
        126 ->
            case gen_tcp:recv(Socket, 2, 5000) of
                {ok, <<Length:16/big>>} -> {ok, Length};
                {error, Reason} -> {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
            end;
        127 ->
            case gen_tcp:recv(Socket, 8, 5000) of
                {ok, <<Length:64/big>>} -> {ok, Length};
                {error, Reason} -> {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
            end;
        Length ->
            {ok, Length}
    end.

sha256_hex(Contents) ->
    string:lowercase(binary:encode_hex(crypto:hash(sha256, Contents))).

get_env(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false ->
            {error, <<"environment variable is not set">>};
        Value ->
            {ok, unicode:characters_to_binary(Value)}
    end.

monotonic_microsecond() ->
    erlang:monotonic_time(microsecond).

otp_release() ->
    unicode:characters_to_binary(erlang:system_info(otp_release)).

runtime_summary() ->
    Schedulers = erlang:system_info(schedulers_online),
    Wordsize = erlang:system_info(wordsize),
    ProcessCount = erlang:system_info(process_count),
    Memory = erlang:memory(total),
    unicode:characters_to_binary(
      io_lib:format(
        "otp=~s schedulers=~p wordsize=~p process_count=~p memory_total_bytes=~p",
        [erlang:system_info(otp_release), Schedulers, Wordsize, ProcessCount, Memory]
      )
    ).

exit(Code) ->
    erlang:halt(Code).
