:- module(journaling,[write_triple/5,
                      initialise_graph/4,
                      finalise_graph/4,
                      set_graph_stream/4,
                      close_graph_stream/4]).
 
/** <module> Journaling
 * 
 * Journaling writes so we can reconstruct the in memory database in the 
 * event of restart.
 * 
 * * * * * * * * * * * * * COPYRIGHT NOTICE  * * * * * * * * * * * * * * *
 *                                                                       *
 *  This file is part of TerminusDB.                                     *
 *                                                                       *
 *  TerminusDB is free software: you can redistribute it and/or modify   *
 *  it under the terms of the GNU General Public License as published by *
 *  the Free Software Foundation, either version 3 of the License, or    *
 *  (at your option) any later version.                                  *
 *                                                                       *
 *  TerminusDB is distributed in the hope that it will be useful,        *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of       *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        *
 *  GNU General Public License for more details.                         *
 *                                                                       *
 *  You should have received a copy of the GNU General Public License    *
 *  along with TerminusDB.  If not, see <https://www.gnu.org/licenses/>. *
 *                                                                       *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 */ 

:- use_module(types).
:- use_module(utils).
:- use_module(database).
:- use_module(prefixes).
 
/** 
 * graph_stream(+G:graph_identifier,-Stream,-Type,-Ext) is det.  
 *
 * Stores the currently associated stream and its type with graph G. 
 */ 
:- dynamic graph_stream/4.

/** 
 * set_graph_stream(+G:graph_identifier,+Stream,+Type,+Ext) is det.  
 *
 * Stores the currently associated stream with graph G and its type. 
 * Raises an error if there is already an associated stream for graph G.
 */
set_graph_stream(Graph_Id,S,Type,Ext) :-
    (   graph_stream(Graph_Id,S0,Type,Ext)
    ->  throw(graph_stream_already_set(Graph_Id,S0,Type,Ext))
    ;   assertz(graph_stream(Graph_Id,S,Type,Ext))
    ).


/** 
 * close_graph_stream(+G,+Stream,+Type,+Ext) is det.  
 *
 * Close stream associated with a given graph.
 */ 
close_graph_stream(Graph_Id,Stream,Type,Ext) :-
    forall(graph_stream(Graph_Id,Stream,Type,Ext),
           (   retractall(graph_stream(Graph_Id,Stream,Type,Ext)),
               flush_output(Stream),
               close(Stream)
           )).

/** 
 * close_graph_streams is det.  
 *
 * Close all streams associated with all graphs.
 */ 
closeStreams :-
    forall(graph_stream(Graph_Id,Stream,Type,Ext),
           close_graph_stream(Graph_Id,Stream,Type,Ext)).

/* 
 * initialise_graph(Graph_ID,Stream,Type,Ext) is semidet.
 */
initialise_graph(Graph_Id,Stream,Type,Ext) :-
    graph_stream(Graph_Id,Stream,Type,Ext),
    (   Ext=ttl
    ->  true % deprecated write_turtle_prelude(Stream)
    ;   Ext=ntr
    ->  throw(unimplemented_storage_type(ntr))
    ;   Ext=hdt
    ->  throw(unimplemented_storage_type(hdt))
    ).

/* 
 * initialise_graph(Graph_ID,Stream,Type,Ext) is semidet.
 */
finalise_graph(Graph,Stream,Type,Ext) :-
    graph_stream(Graph,Stream,Type,Ext),
    (   Ext=ttl
    ->  close_graph_stream(Graph,Stream,Type,Ext)
    ;   Ext=ntr
    ->  throw(unimplemented_storage_type(ntr))
    ;   Ext=hdt
    ->  throw(unimplemented_storage_type(hdt))
    ).

/** 
 * write_triple(+G,+Type,+PX,+PY,+PZ) is det.
 * 
 * Write a triple to graph G where Ext is one of {ttl,ntl,hdt}
 * and Type is one of {pos,neg,chk}
 */ 
write_triple(G,Type,PX,PY,PZ) :-
    debug(write_triple, 'PX ~q      PY ~q      PZ ~q', [PX, PY,PZ]),
    graph_stream(G,Stream,Type,Ext),
    (   Ext=ttl
    ->  write_triple_turtle(PX,PY,PZ,Stream)
    ;   Ext=ntr
    ->  throw(unimplemented_storage_type(ntr))
    ;   Ext=hdt
    ->  throw(unimplemented_storage_type(hdt))
    ;   throw(unimplemented_storage_type(Ext))
    ).

/* 
 * Goal expansion for write_triple in order to 
 * make static code references to ontologies less painful.
 */
user:goal_expansion(write_triple(G,T,A,Y,Z),write_triple(G,T,X,Y,Z)) :-
    \+ var(A),
    global_prefix_expand(A,X).
user:goal_expansion(write_triple(G,T,X,B,Z),write_triple(G,T,X,Y,Z)) :-
    \+ var(B),
    global_prefix_expand(B,Y).
user:goal_expansion(write_triple(G,T,X,Y,C),write_triple(G,T,X,Y,Z)) :-
    \+ var(C),
    \+ C = literal(_),
    global_prefix_expand(C,Z).
user:goal_expansion(write_triple(G,T,X,Y,literal(L)),write_triple(G,T,X,Y,Object)) :-
    \+ var(L),
    literal_expand(literal(L),Object).


/** 
 * write_point_turtle(+Stream,+P) is det. 
 * 
 * Writes a single "point" out.  
 */
write_point_turtle(Stream, P) :-
    (   atom(P) % Do we have a prefix yet? 
    ->  write(Stream,'<'),write(Stream,P),write(Stream,'>')
    ;   debug(journaling, 'Point: ~q~n', [P]), 
        write(Stream,P)
    ).

/** 
 * write_triple_turtle(+X,+Y,+Z,+Stream) is det. 
 * 
 * Writes triple to stream in turtle format.
 *
 * We avoid interleaving by making the write a single atomic action:
 *    a) write first to string
 *    b) then write to stream   
 * 
 * This allows the predicate to be used in multithreading
 */ 
write_triple_turtle(PX,PY,PZ,Stream) :-
    with_output_to(string(String),
		           (current_output(Out),
		            write_point_turtle(Out,PX),write(Out,' '),
		            write_point_turtle(Out,PY),write(Out,' '),
		            write_lit_or_obj_turtle(Out,PZ),
		            write(Out,' .\n')
		           )),
    write(Stream,String). 

/** 
 * quoted_atom_write(Out,Atom) is det.
 * 
 * This writes an atom quoted to the stream Out such that it has double quotes
 * and has no single quotes surrounding regardless of the internal syntax.
 *
 * This is neccessary as atoms print irregularly depending on whether they contain
 * spaces or other special characters.
 */
quoted_write(Out,Atom) :-
    atom(Atom),
    with_output_to(string(String),
                   (
                       current_output(Stream),
                       write_term(Stream,Atom,[character_escapes(true)])
                   )),
    re_replace('^\'','',String,String2),
    re_replace('\'$','',String2,NewString),
    writeq(Out,NewString).
quoted_write(Out,String) :-
    string(String),
    writeq(Out,String).
quoted_write(Out,Number) :-
    number(Number),
    write(Out,'"'),writeq(Out,Number),write(Out,'"').

%:- rdf_meta write_lit_or_obj_turtle(o,r).

write_lit_or_obj_turtle(Stream,literal(type(PT,time(Hour,Minute,Second)))) :-
    !,
    format_time(atom(Atom), '%T', date(0,0,0,Hour,Minute,Second,0,-,false), posix),
    write(Stream,' "'),write(Stream,Atom),write(Stream,'"'),
    write(Stream,'^^'),
    write_point_turtle(Stream,PT).
write_lit_or_obj_turtle(Stream,literal(type(PT,date(Year,Month,Day)))) :-
    !,
    format_time(atom(Atom), '%F', date(Year,Month,Day), posix),
    write(Stream,' "'),write(Stream,Atom),write(Stream,'"'),
    write(Stream,'^^'),
    write_point_turtle(Stream,PT).                     % Prolog date time 
write_lit_or_obj_turtle(Stream,literal(type(PT,date(Year,Month,Day,Hour,Minute,Second,_Off,_TZ,_DST)))) :-
    !,
    format_time(atom(Atom), '%FT%T%:z', date(Year,Month,Day,Hour,Minute,Second,0,-,false), posix),
    write(Stream,' "'),write(Stream,Atom),write(Stream,'"'),
    write(Stream,'^^'),
    write_point_turtle(Stream,PT).
write_lit_or_obj_turtle(Stream,literal(type(PT,date_time(Year,Month,Day,Hour,Minute,Second)))) :-
    !,
    format_time(atom(Atom), '%FT%T%:z', date(Year,Month,Day,Hour,Minute,Second,0,-,false), posix),
    write(Stream,' "'),write(Stream,Atom),write(Stream,'"'),
    write(Stream,'^^'),
    write_point_turtle(Stream,PT).
write_lit_or_obj_turtle(Stream,literal(type(PT,date_time(Year,Month,Day,Hour,Minute,Second,Z)))) :-
    !,
    format_time(atom(Atom), '%FT%T%:z', date(Year,Month,Day,Hour,Minute,Second,Z,-,false), posix),
    write(Stream,' "'),write(Stream,Atom),write(Stream,'"'),
    write(Stream,'^^'),
    write_point_turtle(Stream,PT).
%% should not need this duplicated xsd:string and full URL
write_lit_or_obj_turtle(Stream,literal(type('http://www.w3.org/2001/XMLSchema#string',Lit))) :-
    !,
    write(Stream,' '),quoted_write(Stream,Lit),
    write(Stream,'^^'),write_point_turtle(Stream,'http://www.w3.org/2001/XMLSchema#string').
write_lit_or_obj_turtle(Stream,literal(type(xsd:string,Lit))) :-
    !,
    write(Stream,' '),quoted_write(Stream,Lit),
    write(Stream,'^^'),write_point_turtle(Stream,xsd:string).
write_lit_or_obj_turtle(Stream,literal(type(PT,Lit))) :-
    debug(journaling,'Literal: ~q~nType: ~q~n',[Lit, PT]),
    !,
    write(Stream,' '),quoted_write(Stream,Lit),
    write(Stream,'^^'),write_point_turtle(Stream,PT).
write_lit_or_obj_turtle(Stream,literal(lang(Lang,Lit))) :-
    !,
    write(Stream,' '),quoted_write(Stream,Lit),
    write(Stream,'@'),write(Stream,Lang).
write_lit_or_obj_turtle(Stream,PZ) :-
    write_point_turtle(Stream,PZ).
    
