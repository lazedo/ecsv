
% This file is part of ecsv released under the MIT license.
% See the LICENSE file for more information.

-module(ecsv_parser).
-author("Nicolas R Dufour <nicolas.dufour@nemoworld.info>").

-include("ecsv.hrl").

%
% This module is the raw csv parser.
% It will expect receiving:
% - {char, Char} for each character in a csv file
% - {eof} when the file is over
%
% It will send to the ResultPid (given to the funtion start_parsing):
% - {newline, NewLine} for each parsed line
% - {done} when the parsing is done (usually because eof has been sent)
%
% This parser is based on the blog post written by Andy Till located
% here http://andrewtill.blogspot.com/2009/12/erlang-csv-parser.html.
%
% This parser supports well formed csv files which are
% - a set of lines ending with a \n
% - each line contains a set of fields separated with a comma (,)
% - each field value can be enclosed with double quote (") ONLY
% - each field value can be empty
%
% Please note:
% - This parser has no failsafe mechanism if the file is badly formed!
%   But the line a,,,,,\n is perfectly fine.
% - This parser doesn't allow a return (\n) in a field value!
%

-export([start_parsing/1, start_parsing/2]).

-define(EMPTY_STRING, []).

%% @doc start parsing a csv stream and send the result to ResultPid
start_parsing(ResultPid) ->
    DefaultOptions = default_options(),
    start_parsing(ResultPid, DefaultOptions).

start_parsing(ResultPid, Options) ->
    ready(ResultPid, Options).

% -----------------------------------------------------------------------------

default_options() ->
    #ecsv_opts{ }.

% the ready state is the initial one and also the most common state
% through the parsing
ready(ResultPid, Options) ->
    ready(ResultPid, Options, [], []).
ready(ResultPid, Options, ParsedCsv, CurrentValue) ->
    Delimiter = Options#ecsv_opts.delimiter,
    receive
        {eof} ->
            NewLine = lists:reverse([lists:reverse(CurrentValue) | ParsedCsv]),
            send_line(ResultPid, NewLine),
            send_eof(ResultPid);
        {char, Char} when (Char == $") ->
            % pass an empty string to in_quotes as we do not want the
            % preceeding characters to be included, only those in quotes
            in_quotes(ResultPid, Options, ParsedCsv, ?EMPTY_STRING, Char);
        {char, Char} when Char == Delimiter ->
            ready(
                ResultPid, Options,
                [lists:reverse(CurrentValue) | ParsedCsv], ?EMPTY_STRING);
        {char, Char} when Char == $\n ->
            % a new line has been parsed: time to send it back
            NewLine = lists:reverse([lists:reverse(CurrentValue) | ParsedCsv]),
            ResultPid ! {newline, NewLine},
            ready(ResultPid, Options, [], ?EMPTY_STRING);
        {char, Char} when Char == $\r ->
            % ignore line feed characters
            ready(ResultPid, Options, ParsedCsv, CurrentValue);
        {char, Char} ->
            ready(ResultPid, Options, ParsedCsv, [Char | CurrentValue])
    end.

% the in_quotes state adds all chars it receives to the value string until
% it receives a char matching the initial quote in which case it moves to
% the skip_to_delimiter state.
in_quotes(ResultPid, Options, ParsedCsv, CurrentValue, QuoteChar) ->
    receive
        {eof} ->
            NewLine = lists:reverse([lists:reverse(CurrentValue) | ParsedCsv]),
            send_line(ResultPid, NewLine),
            send_eof(ResultPid);
        {char, Char} when Char == QuoteChar ->
            skip_to_delimiter(
                ResultPid, Options,
                [lists:reverse(CurrentValue) | ParsedCsv]);
        {char, Char} ->
            in_quotes(ResultPid, Options, ParsedCsv, [Char | CurrentValue], QuoteChar)
    end.

% the skip_to_delimiter awaits chars which will get thrown away, when a
% value delimiter is received the machine moves to the ready state again.
skip_to_delimiter(ResultPid, Options, ParsedCsv) ->
    receive
        {eof} ->
            NewLine = lists:reverse(ParsedCsv),
            send_line(ResultPid, NewLine),
            send_eof(ResultPid);
        {char, Char} when Char == Options#ecsv_opts.delimiter ->
            ready(ResultPid, Options, ParsedCsv, ?EMPTY_STRING);
        {_} ->
            skip_to_delimiter(ResultPid, Options, ParsedCsv)
    end.

% ----------------------------------------------------------------------------

send_line(ResultPid, NewLine) ->
    ResultPid ! {newline, NewLine}.

send_eof(ResultPid) ->
    ResultPid ! {done}.
