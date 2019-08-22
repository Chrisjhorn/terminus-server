:- module(schema_util, [
              % module construction
              database_module/2,
              % utils
              calculate_subsumptionOf/3,
              entity/2
          ]).

/** <module> Schema Util
 * 
 * Utilities to assist in the compilation of schemata.
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
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */


:- use_module(library(database)).
:- use_module(library(types)).
:- use_module(library(schema_definitions)).

/* 
 * graph_module(+Database:database, -Module:atom) is det. 
 */
database_module(Database,Module) :-
    database_name(Database,Module).

calculate_subsumptionOf(CC, CP, Database) :-
    is_database(Database),
    !,
    database_module(Database, Module),
    calculate_subsumptionOf(CC, CP, Module).

calculate_subsumptionOf(CC, CC, Module) :-
    Module:class(CC).
calculate_subsumptionOf(CC, CP, Module) :-
    Module:subClassOf(CC, CZ),
    calculate_subsumptionOf(CZ, CP, Module).
calculate_subsumptionOf(CC, CP, Module) :-
    Module:class(CC),
    Module:unionOf(CZ, CC),
    calculate_subsumptionOf(CZ,CP,Module).
calculate_subsumptionOf(CC, CP, Module) :-
    Module:class(CC),
    Module:disjointUnionOf(CZ, CC),
    calculate_subsumptionOf(CZ, CP, Module).
calculate_subsumptionOf(CC, CP, Module) :-
    Module:class(CC),
    Module:intersectionOf(CC, CZ),
    calculate_subsumptionOf(CZ, CP, Module).
calculate_subsumptionOf(CC, CP, Module) :-
    % the tbox version does extra work in anonymousEquivalentClass, but why?
    Module:equivalentClass(CC, CZ),
    calculate_subsumptionOf(CZ, CP, Module).
calculate_subsumptionOf(_,'http://www.w3.org/2002/07/owl#Thing',_).
calculate_subsumptionOf('http://www.w3.org/2002/07/owl#Nothing',_,_).
% Always available...
calculate_subsumptionOf('https://datachemist.net/ontology/dcog#Entity',
                        'https://datachemist.net/ontology/dcog#Entity',_).

term_expansion(generate_owl_predicates, Terms) :-
    findall(Predicate,
            schema_definitions:schema_predicate(Predicate),
            Predicates),

    schema_definitions:util_predicates(Utils),

    findall(Pair,
            (   member(Predicate/Arity, Predicates),
                \+ member(Predicate/Arity, Utils),
                functor(Inner_Fn, Predicate, Arity),
                Inner_Fn =.. [_|Inner_Arguments],
                append(Inner_Arguments, [Module], Arguments),
                append(Inner_Arguments, [Graph_Module], GraphVersion_Arguments),
                Fn =.. [Predicate|Arguments],
                Graph_Fn =.. [Predicate|GraphVersion_Arguments],
                Definition1 = (Fn :- is_graph(Module),
                                     !,
                                     graph_module(Module, Graph_Module),
                                     Graph_Fn),
                Definition2 = (Fn :- Module:Inner_Fn),
                Pair = [Definition1, Definition2],
                Arity_Plus1 is Arity + 1,
                export(Predicate/Arity_Plus1)
            ),
            Pairs),
    flatten(Pairs, Terms).

generate_owl_predicates.

entity(Class, Graph) :-
    is_graph(Graph),
    !,
    graph_module(Graph, Module),
    Module:subsumptionOf(Class, 'https://datachemist.net/ontology/dcog#Entity').

entity(Class, Module) :-
    Module:subsumptionOf(Class, 'https://datachemist.net/ontology/dcog#Entity').
