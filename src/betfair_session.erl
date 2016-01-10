-module(betfair_session).

-export([new_session/1]).

-define(URL_ENCODED, "application/x-www-form-urlencoded").


%%------------------------------------------------------------------------------
%% Types
%%------------------------------------------------------------------------------

-type token() :: string().

-export_type([credentials/0]).
-export_type([token/0]).

-type credentials() :: #{username => string(),
                         password => string(),
                         app_key=> string()}.


%%------------------------------------------------------------------------------
%% API functions
%%------------------------------------------------------------------------------

%% TODO: Tidy and simplify this module.
%% TODO: Do not pass in all opts - only pass in what is needed

-spec new_session(list(tuple())) -> pid() | {ok, string()}.
new_session(Opts) ->
    Credentials = proplists:get_value(credentials, Opts),
    SSlOpts = proplists:get_value(ssl, Opts),
    Endpoint = proplists:get_value(identity_endpoint, Opts),
    Conn = open_conn(Endpoint, SSlOpts),
    {ok, SessionToken} = receive_token(Conn, maps:from_list(Credentials)),
    ok = gun:shutdown(Conn),
    {ok, SessionToken}.


%%------------------------------------------------------------------------------
%% Internal functions
%%------------------------------------------------------------------------------

-spec open_conn(list(), list(tuple)) -> pid().
open_conn(Endpoint, SSlOpts) ->
    {ok, Connection} = gun:open(Endpoint, 443,
                                #{transport => ssl, transport_opts => SSlOpts}),
    {ok, _} = gun:await_up(Connection),
    Connection.

-spec receive_token(pid(), map()) -> {ok, token()} | any().
receive_token(Connection, #{app_key := Appkey} = Credentials) ->
    ReqBody = betfair_http:url_encode(maps:without([app_key], Credentials)),
    ReqHeaders = [betfair_http:hdr(<<"Content-Type">>, ?URL_ENCODED),
                  betfair_http:hdr(<<"X-Application">>, Appkey)],
    Stream = gun:post(Connection, "/api/certlogin", ReqHeaders, ReqBody),
    receive_data(Connection, Stream).


-spec receive_data(pid(), reference()) -> {ok, token()} | any().
receive_data(Connection, Stream) ->
    case gun:await(Connection, Stream) of
        {response, fin, _Status, _Headers} ->
            {error, no_data};
        {response, nofin, _Status, _Headers} ->
            {ok, Body} = gun:await_body(Connection, Stream),
            Response = jsx:decode(Body, [return_maps, {labels, atom}]),
            token(Response)
    end.

-spec token(map()) -> {ok, token()} | {error, string()}.
token(#{sessionToken := Token, loginStatus := _Reason}) ->
    {ok, Token};
token(#{token := Token, status := <<"SUCCESS">>}) ->
    {ok, Token};
token(#{loginStatus := Reason}) ->
    {error, Reason};
token(#{error := Reason}) ->
    {error, Reason}.