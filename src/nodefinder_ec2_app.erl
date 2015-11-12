%%------------------------------------------------------------------------------
%% @doc ec2-describe-instances based nodefinder service.
%% @end
%%------------------------------------------------------------------------------
-module(nodefinder_ec2_app).
-behaviour (application).

-export([
    discover/0,
    discover_ip_addresses/0,
    first_security_group/0,
    start/0,
    start/2,
    stop/0,
    stop/1
]).

-define(APPLICATION, nodefinder_ec2).

%%------------------------------------------------------------------------------
%%                                Public
%%------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Initiate a discovery request.  Discovery is synchronous; the
%% results are returned.
%% @end
%%------------------------------------------------------------------------------
-spec discover() -> {ok, [{atom(), pong|pang|timeout}]}.
discover() ->
    nodefinder_ec2_srv:discover().

%%------------------------------------------------------------------------------
%% @doc Initiate a discovery request (IP addresses).  Discovery is synchronous; the
%% results are returned.
%% @end
%%------------------------------------------------------------------------------
-spec discover_ip_addresses() -> {ok, [{atom(), pong|pang|timeout}]}.
discover_ip_addresses() ->
    nodefinder_ec2_srv:discover_ip_addresses().

%%------------------------------------------------------------------------------
%%                        application callbacks                        
%%------------------------------------------------------------------------------

%% @hidden
start() ->
    inets:start(),
    crypto:start(),
    application:start(?APPLICATION).

%% @hidden
start(_Type, _Args) ->
    Group = case application:get_env(?APPLICATION, group) of
                {ok, G} -> G;
                _       -> first_security_group()
            end,
    {ok, PingTimeoutSec} = application:get_env(?APPLICATION, ping_timeout_sec),
    AKI = get_p(access, "AWS_ACCESS_KEY_ID"),
    SAK = get_p(secret, "AWS_SECRET_ACCESS_KEY"),
    nodefinder_ec2_sup:start_link(  Group,
                                    PingTimeoutSec*1000,
                                    AKI,
                                    SAK).

%% @hidden
stop () -> 
  application:stop(?APPLICATION).

%% @hidden
stop (_State) ->
  ok.

%%------------------------------------------------------------------------------
%%                               Private                               
%%------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc get application parameter from .app file, 
%%      if not exist check environment variable
%% @private
%% @end
%%------------------------------------------------------------------------------
-spec get_p(Atom::atom(), Env::string())-> error|term().
get_p(Atom, Env)->
    case application:get_env(?APPLICATION, Atom) of
        {ok, Value} ->
            Value;
        undefined ->
            case os:getenv(Env) of
                false -> error;
                Value -> Value
            end
    end.

%%------------------------------------------------------------------------------
%% @doc get first EC2 security group
%% @end
%%------------------------------------------------------------------------------
-spec first_security_group() -> string().    
first_security_group() ->
    Url = "http://169.254.169.254/2007-08-29/meta-data/security-groups",
    case httpc:request(Url) of
        {ok, {{_HttpVersion, 200, _Reason}, _Headers, Body}} ->
            string:substr(Body, 1, string:cspan (Body, "\n"));
        _BadResult ->
            %erlang:error({ http_request_failed, Url, BadResult })
            "default"
    end.

