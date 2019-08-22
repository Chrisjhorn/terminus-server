:- module(database,[
              database_instance/2,
              database_schema/2,
              database_error_instance/2,
              database_error_schema/2,
              database_inference/2,
              make_database/2,
              make_raw_database/2,
              make_database_from_database_name/2,
              database_identifiers/2,
              terminus_database_name/1,
              terminus_context/1,
              terminus_database/1
          ]).

/** <module> Implementation of database management
 * 
 * This module helps other modules with the representation of databases 
 * by bundling collections of graphs as objects with some convenience operators.
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

:- use_module(library(utils)).
:- use_module(library(types)).
:- use_module(library(woql_term)).

/* 
 * Database term accessors.
 */ 
database_name(database(Name, _ , _ ,_, _, _),Name).

database_instance(database(_, Instance, _ ,_, _, _),Instance).

database_inference(database(_, _,Inference,_,_,_),Inference).

database_schema(database(_, _,_,Schema,_,_),Schema).

database_error_instance(database(_,_,_,_,Error_Instance,_), Error_Instance).

database_error_schema(database(_,_,_,_,_,Error_Schema), Error_Schema).

/** 
 * make_database(+DatabaseList:list,-Database:database) is det.
 * 
 * Create a graph from a list containing some number of graph elements.
 * [instance=Instance,schema=Schema...]
 */ 
make_database(DatabaseList, Database) :-
    Database = database(Name,Instance,Inference,Schema,Error_Instance,Error_Schema),
    get_key(name,DatabaseList,Name,none),
    get_key(schema,DatabaseList,Schema,none),
    get_key(instance,DatabaseList,Instance,none),
    get_key(inference,DatabaseList,Inference,none),
    get_key(error_schema,DatabaseList,Error_Schema,none),
    get_key(error_instance,DatabaseList,Error_Instance,none),

    schema:database_module(Database,Module),
    schema:ensure_schema_in_module(Database,Module).

/** 
 * make_database(+DatabaseList:list,-Database:database) is det.
 * 
 * Create a graph from a list containing some number of graph elements.
 * [instance=Instance,schema=Schema...]
 *  
 * This does NO schema compilation and is only used during initial pre-testing for cycles.
 */ 
make_raw_database(DatabaseList, Database) :-
    Database = database(Name,Instance,Inference,Schema,Error_Instance,Error_Schema),
    get_key(name,DatabaseList,Name,[]),
    get_key(schema,DatabaseList,Schema,[]),
    get_key(instance,DatabaseList,Instance,[]),
    get_key(inference,DatabaseList,Inference,[]),
    get_key(error_schema,DatabaseList,Error_Schema,[]),
    get_key(error_instance,DatabaseList,Error_Instance,[]).

/** 
 * database_identifiers(+Database:database, -DatabaseList:list(database_identifier)) is det.
 * 
 * Create a list of names of the graphs elements contained in a graph structure. 
 */ 
database_identifiers(Database,Names) :-
    database_instance(Database,GI),
    database_inference(Database,Inf),
    database_schema(Database,GS),
    database_error_instance(Database,EI),
    database_error_schema(Database,ES),
    exclude(is_empty_graph_name,[GI,Inf,GS,EI,ES], Names).

/* 
 * terminus_database_name(Database_Name) is det. 
 * 
 * The name of the current terminus database.
 */ 
terminus_database_name(Database_Name) :-
    config:server_name(Server),
    atomic_list_concat([Server,'/terminus'],Database_Name).

/** 
 * terminus_context(Context : dictionary) is det.
 * 
 * JSON-LD of terminus context. 
 */ 
terminus_context(_{
                     doc : Doc,
                     schema : Schema,
                     terminus : 'https://datachemist.net/ontology/terminus#'
                   }) :-
    config:server_name(Server),
    atomic_list_concat([Server,'/document/'],Doc),
    atomic_list_concat([Server,'/schema/'],Schema).


/* 
 * terminus_database(Database).
 * 
 * Since this is prior to all other aspects of graph 
 * management, we need to set the information manually. 
 */ 
terminus_database(Database) :-
    terminus_database_name(Database_Name),
    interpolate([Database_Name,'/terminus/document'],Instance),
    interpolate([Database_Name,'/terminus/inference'],Inference),
    interpolate([Database_Name,'/terminus/schema'],Schema),
    make_database([name=Database_Name,
                   schema=[Schema],
                   inference=[Inference],
                   instance=[Instance]], Database).

/** 
 * make_database_from_database_name(+URI,-Database) is det.
 * 
 */ 
make_database_from_database_name(Database_Name,Database) :-
    % Need a special case for the master database
    (   terminus_database_name(Database_Name)
    ->  terminus_database(Database)
    ;   terminus_database_name(Terminus_Name),
        % this appears at first to be circular, but we never call
        % connect inside of the connect for terminus because we
        % call terminus_database/1 instead.
        connect(Terminus_Name,Terminus_DB),
        
        ask(Terminus_DB,
            where(
                (
                    t( DB_Resource , terminus/id, Database_Name ^^ (xsd/anyURI)), 
                    t( DB_Resource , rdf/type , terminus/'Database')
                )
            )),
        
        findall(Schema, 
                ask(Terminus_DB,
                    where(t( DB_Resource , terminus/schema, Schema ^^ (xsd/anyURI)))
                   ),
                Schemata),
        
        findall(Instance, 
                ask(Terminus_DB,
                    where(t( DB_Resource , terminus/instance, Instance ^^ (xsd/anyURI)))
                   ),
                Instances),

        findall(Inference, 
                ask(Terminus_DB,
                    where(t( DB_Resource , terminus/instance, Inference ^^ (xsd/anyURI)))
                   ),
                Inferences),
        
        make_database([name=Database_Name,
                       schema=Schemata,
                       instance=Instances,
                       inference=Inferences
                      ], Database)
    ).

        
   

            
                                
        
    
