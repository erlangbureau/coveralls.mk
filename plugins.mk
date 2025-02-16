.PHONY: coveralls

CT_COVERDATA = $(shell ls -1rt `find logs -type f -name \*.coverdata 2>/dev/null` | tail -n1)
COVERALLS_JSON = logs/coveralls.json
COVERALLS_URL = https://coveralls.io/api/v1/jobs
COVERALLS_SERVICE_NAME = github
COVERALLS_SERVICE_JOB_ID = $(GITHUB_RUN_ID)
COVERALLS_REPO_TOKEN = $(GITHUB_TOKEN)
COVERALLS_COMMIT_SHA = $(GITHUB_SHA)
COVERALLS_SERVICE_NUMBER = $(GITHUB_RUN_NUMBER)

define coveralls_collect.erl
    FunSourceFile = fun(Mod) ->
        try Mod:module_info(compile) of
            Info ->
                Source = proplists:get_value(source, Info),
                {ok, Source}
        catch
            error:undef:_ ->
                {error, source_not_found}
        end
    end,
    FunLineCoverage = fun 
        FunLineCoverage(Line, EndLine, _Coverage, Acc) when Line > EndLine ->
            lists:reverse(Acc);
        FunLineCoverage(Line, EndLine, [], Acc) ->
            FunLineCoverage(Line + 1, EndLine, [], [null | Acc]);
        FunLineCoverage(1, EndLine, [{{_Mod, 0}, _Calls} | Rest], Acc) ->
            FunLineCoverage(1, EndLine, Rest, Acc);
        FunLineCoverage(Line, EndLine, [{{_Mod, Line}, Calls} | Rest], Acc) ->
            FunLineCoverage(Line + 1, EndLine, Rest, [Calls | Acc]);
        FunLineCoverage(Line, EndLine, Coverage, Acc) ->
            FunLineCoverage(Line + 1, EndLine, Coverage, [null | Acc])
    end,
    FunFixPath = fun(SrcFile) ->
        {ok, Cwd} = file:get_cwd(),
        Cwd2 = re:replace(Cwd, "/(logs|\.eunit)/.+$$", "", [{return, list}]),
        Path = string:substr(SrcFile, length(Cwd2) + 2),
        unicode:characters_to_binary(Path)
    end,
    FunCheckCoverage = fun(Module) ->
        {ok, SourceFile} = FunSourceFile(Module),
        {ok, Source} = file:read_file(SourceFile),
        SourceLines = binary:split(Source, <<"\n">>, [global]),
        {ok, Coverage} = cover:analyse(Module, calls, line),
        CoverageLines = FunLineCoverage(1, length(SourceLines), Coverage, []),
        #{
            <<"name">> => FunFixPath(SourceFile),
            <<"source">> => Source,
            <<"coverage">> => CoverageLines
        }
	end,
    true = code:add_patha("ebin/"),
    io:format(user, "Analysing file: ~p~n", ["$(CT_COVERDATA)"]),
    ok = cover:import("$(CT_COVERDATA)"),
    Modules = cover:imported_modules(),
    CoverageData = lists:map(FunCheckCoverage, Modules),
    ReqMap = #{
        <<"service_name">>      => <<"$(COVERALLS_SERVICE_NAME)">>,
        <<"service_job_id">>    => <<"$(COVERALLS_SERVICE_JOB_ID)">>,
        <<"repo_token">>        => <<"$(COVERALLS_REPO_TOKEN)">>,
        <<"commit_sha">>        => <<"$(COVERALLS_COMMIT_SHA)">>,
        <<"service_number">>    => <<"$(COVERALLS_SERVICE_NUMBER)">>,
        <<"source_files">>      => CoverageData
    },
    Json = jsx:encode(ReqMap),
    file:write_file("$(COVERALLS_JSON)", Json),
    io:format("Coverage data written to $(COVERALLS_JSON)~n"),
	halt().
endef

define coveralls_send.erl
    ok = application:start(asn1),
    ok = application:start(crypto),
    ok = application:start(public_key),
    ok = application:start(ssl),
    ok = application:start(inets),
    FunGenerateBody = fun(Boundary) ->
        Boundary2 = unicode:characters_to_binary(Boundary),
        {ok, Payload} = file:read_file("$(COVERALLS_JSON)"),
        <<"--", Boundary2/binary, "\r\n",
            "Content-Disposition: form-data; name=\"coverage\"; filename=\"coverage.json\"\r\n",
            "Content-Type: application/octet-stream\r\n\r\n",
            Payload/binary, "\r\n",
            "--", Boundary2/binary, "--\r\n">>
    end,
    Boundary = "----------coveralls.mk",
    Type = "multipart/form-data; boundary=" ++ Boundary,
    Body = FunGenerateBody(Boundary),
    case httpc:request(post, {"$(COVERALLS_URL)", [], Type, Body}, [], []) of
        {ok, {{_Version, 200, _HttpMsg}, _RespHeaders, _RespBody}} ->
            io:format("Coverage report sent to coveralls.io~n"),
            ok;
        {ok, {{_Version, _Code, _HttpMsg}, _RespHeaders, RespBody}} ->
            io:format("Coverage report not sent to coveralls.io~n"),
            {error, RespBody}
    end,
	halt().
endef

define coveralls_collect
	$(verbose) $(call erlang,$(call coveralls_collect.erl))
endef

define coveralls_send
	$(verbose) $(call erlang,$(call coveralls_send.erl))
endef

coveralls-collect: tests
	$(verbose) $(call coveralls_collect)

coveralls-send: coveralls-collect
	$(verbose) $(call coveralls_send)

help::
	$(verbose) printf "%s\n" "" \
		"coveralls targets:" \
		"  coveralls-collect    Prepare coverage data" \
		"  coveralls-send       Send coverage data to coveralls"
