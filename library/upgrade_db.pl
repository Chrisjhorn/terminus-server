:- module(upgrade_db,[get_db_version/1,
                      set_db_version/1,
                      maybe_upgrade/0
                     ]).

/** <module> Utilities to check and upgrade the database version
 * 
 * This module is meant to upgrade old versions of the database to new database 
 * formats. 
 * 
 * We want to create chaining rules for application of lifting operations so that we 
 * only have to test each upgrade from V to V+1, but can apply arbitrary version 
 * lifts. This is done using term expansion from run_upgrade_step/2 which automatically 
 * constructs upgrade_step/2 so that we can test accessibility with accessible/2.
 *
 * In order to add an upgrade step, please add a clause to run_upgrade_step/2 and 
 * change the current version set in database_version/1
 *
 * i.e.  

 run_upgrade_step('1.2','1.3') :-
     % do stuff here. 
     % ... 
     true.

 * * * * * * * * * * * * * COPYRIGHT NOTICE  * * * * * * * * * * * * * * *
 *                                                                       *
 *  This file is part of TerminusDB.                                      *
 *                                                                       *
 *  TerminusDB is free software: you can redistribute it and/or modify    *
 *  it under the terms of the GNU General Public License as published by *
 *  the Free Software Foundation, either version 3 of the License, or    *
 *  (at your option) any later version.                                  *
 *                                                                       *
 *  TerminusDB is distributed in the hope that it will be useful,         *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of       *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        *
 *  GNU General Public License for more details.                         *
 *                                                                       *
 *  You should have received a copy of the GNU General Public License    *
 *  along with TerminusDB.  If not, see <https://www.gnu.org/licenses/>.  *
 *                                                                       *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

:- use_module(utils,[interpolate/2]).
:- use_module(file_utils).
:- use_module(library(pcre)).

       
/** 
 * database_version(-Version) is det. 
 * 
 * Supplies the current version number of the DB
 */ 
database_version('0.1.1').

/*
 * get_db_version(-Version) is det.
 * 
 * Reports the version associated with the current backing store
 */
get_db_version(Version) :-
    db_path(DB_Path),
    interpolate([DB_Path,'VERSION'],Version_File),
    (   exists_file(Version_File)
    ->  setup_call_cleanup(
            open(Version_File,read,Stream),
            (   read_string(Stream, "\n", "\r", _End, String),
                atom_string(Version,String)
            ),
            close(Stream)        
        )
    ;   Version = none).
 
/* 
 * set_db_version(+Version) is det.
 * 
 * Set the Database version
 */ 
set_db_version(Version) :- 
    storage_path(DB_Path),
    interpolate([DB_Path,'VERSION'],Version_File),
    setup_call_cleanup(
        open(Version_File,update, Stream),
        write_term(Stream,Version,[quoted(true),fullstop(true)]),
        close(Stream)
    ).

/* 
 * guess_collection_name(+Graph_Name,-Collection) is semidet.
 *
 * Try to guess the collection name of graph
 */
/* 
Collections are gone. 

guess_collection_name(Graph_Name,Collection) :-
    re_matchsub('(?<Collection>(.*))%2fgraph%2f(main|model|import|error).*',
                Graph_Name,
                Dict, []),
    get_dict('Collection',Dict,Collection).
*/

/* 
 * accessible(Version1,Version2,Path) is det. 
 * 
 * Determines if one version is accessible from another
 */
accessible(Version,Version,[]).
accessible(Version1,Version2,[Version1,Version2]) :-
    upgrade_step(Version1,Version2).
accessible(Version1,Version2,[Version1|Path]) :-
    upgrade_step(Version1,VersionX),
    accessible(VersionX, Version2, Path).

maybe_upgrade :-
    database_version(Target_Version),
    get_db_version(Current_Version),
    (   accessible(Current_Version, Target_Version, Path)
    ->  run_upgrade(Path)
    ;   format(atom(M), 'The version ~q is not accessible from database version ~q', [Target_Version,Current_Version]),
        throw(error(M))
    ).

run_upgrade([]).
run_upgrade([_Last_Version]).
run_upgrade([Version1,Version2|Rest]) :-
    run_upgrade_step(Version1,Version2),
    run_upgrade([Version2|Rest]).

/* 
 * upgrade_step(Version1,Version2) is semidet.
 * 
 * Describes if there is an upgrade from Version1 to Version2
 */
:- discontiguous upgrade_step/2.

/* 
 * We do term expansion to add a upgrade_step/2 with the two 
 * head terms from run_upgrade_step/2 so we can check accessibility
 * of an upgrade.
 */
user:term_expansion((run_upgrade_step(X,Y):-Body),
                    [(run_upgrade_step(X,Y):-Body),
                     upgrade_step(X,Y)]).

/* 
 * run_upgrade_step(X,Y) is nondet.
 * 
 * Perform an upgrade step from version X, to version Y
 *
 * NOTE: shortcuts should go first in the clause order.
 */ 
:- discontiguous run_upgrade_step/2.
/* 

Left as documentation  - we want no upgrade yet as we've no dbs in the wild.

run_upgrade_step(none,'0.1.0') :-
    db_path(Path), 
    subdirectories(Path,Graph_Names),
    forall(
        member(Graph_Name,Graph_Names),
        (
            (   guess_collection_name(Graph_Name,Collection_Name)
            ->  interpolate([Path,Collection_Name], Collection_Path),
                interpolate([Path,Graph_Name], Graph_Path),
                ensure_directory(Collection_Path), 
                mv(Graph_Path,Collection_Path),
                interpolate([Collection_Path,'/COLLECTION'], Collection_Marker),
                touch(Collection_Marker)
            ;   true % not really a graph 
            )
        )
    ),
    set_db_version('0.1.0').
*/ 
