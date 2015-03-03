%% @hidden
%% @doc ec2-describe-instances based node discovery service.
%% @end

-module(nodefinder_ec2_srv).

-behaviour(gen_server).

% API
-export ([start_link/4,
          discover/0 ]).
         
% gen_server callbacks
-export ([ init/1,
           handle_call/3,
           handle_cast/2,
           handle_info/2,
           terminate/2,
           code_change/3]).

-define(APPLICATION, nodefinder_ec2).

-record (state, { group,
                  ping_timeout,
                  access,
                  secret
}).

-define(APIVERSION, "2014-10-01").

%-=====================================================================-
%-                                Public                               -
%-=====================================================================-

start_link (Group, PingTimeout, Access, Secret)
  when is_list (Group),
       is_integer (PingTimeout),
       is_list (Access),
       is_list (Secret) ->
  gen_server:start_link 
    ({ local, ?MODULE }, 
     ?MODULE, 
     [ Group, PingTimeout, Access, Secret ], 
     []);
start_link (Group, PingTimeout, error, error) 
  when is_list (Group),
	   is_integer (PingTimeout) ->
    case util:is_amazon_instance() of
        true  -> {error, missing_aki_and_ask};
        false -> {ok, spawn(fun() -> timer:sleep(infinity) end)}
    end.


discover() ->
  gen_server:call(?MODULE, discover, 60000).

%-=====================================================================-
%-                         gen_server callbacks                        -
%-=====================================================================-

init ([ Group, PingTimeout, Access, Secret  ]) ->
  pong = net_adm:ping (node ()), % don't startup unless distributed

  process_flag (trap_exit, true),
  State = #state{ group = Group,
                  ping_timeout = PingTimeout,
                  access = Access,
                  secret = Secret },
  discover (State),
  { ok, State }.

handle_call (discover, _From, State) -> 
  { reply, { ok, discover (State) }, State };
handle_call (_Request, _From, State) -> 
  { noreply, State }.

handle_cast (_Request, State) -> { noreply, State }.

handle_info (_Msg, State) -> { noreply, State }.

terminate (_Reason, _State) -> ok.

code_change (_OldVsn, State, _Extra) -> { ok, State }.

%-=====================================================================-
%-                               Private                               -
%-=====================================================================-

async (Fun, Timeout) ->
  Me = self (),
  Ref = make_ref (),
  spawn (fun () ->
           { ok, _ } = timer:kill_after (Timeout),
           Me ! { Ref, Fun () }
         end),

  Ref.

collect (Key, Timeout) ->
  receive
    { Key, Status } -> Status
  after Timeout ->
    timeout
  end.

discover (State) ->
    
  Group     = State#state.group,
  Timeout   = State#state.ping_timeout,
  Access    = State#state.access,
  Secret    = State#state.secret,

  % if name is short, we need to call get_hostname on other names to shorten them
  LongName = net_kernel:longnames(),
  {ok,Endpoint} = application:get_env(?APPLICATION, endpoint),
  [ { Node, collect(Key2, Timeout) } ||
    { Node, Key2 } <- 
      [ { Node, start_ping(Node, Timeout) } ||
        { Host, { ok, NamesAndPorts } } <- 
          [ { Host, collect (Key, Timeout) } ||
            { Host, Key } <- [ {Host, start_names(Host, Timeout)} || Host<-awssign:describe_instances(Group, Endpoint, ?APIVERSION, Access, Secret) ] ],
        { Name, _ } <- NamesAndPorts,
      Node <- [ a(Name ++ "@" ++ (case LongName of 
									  false -> get_hostname(Host);
									  true  -> Host
								  end)) ] ] ].

get_hostname(FQDN) ->
    case string:tokens(FQDN,".") of
        [Host|_] -> Host;
        Host     -> Host
    end.


start_names(Host, Timeout) ->
  async(fun() -> net_adm:names(a(Host)) end, Timeout).

start_ping(Node, Timeout) ->
  async(fun() -> net_adm:ping(a(Node)) end, Timeout).

a(Name) when is_atom(Name) -> Name;
a(Name) when is_list(Name) -> list_to_atom(Name).


