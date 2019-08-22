:- module(database_utils,[
              create_db/1,
              delete_db/1
          ]).

/** <module> Database Utilities
 * 
 * Various database level utilities. This is a layer above the triple store 
 * in terms of logic, and placed here as we want to be able to make use 
 * of WOQL and other libraries without circularity.
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

:- use_module(library(file_utils)).
:- use_module(library(triplestore)).
:- use_module(library(utils)).
:- use_module(library(journaling)).

/** 
 * create_db(+DB:atom) is semidet.
 * 
 * Create a new empty graph
 */
create_db(DB) :-
    
    % create the graph if it doesn't exist
    graph_directory(DB,document,Document_Path),
    ensure_directory(Document_Path),
    
    graph_directory(DB,schema,Schema_Path),
    ensure_directory(Schema_Path),
    
    make_checkpoint_directory(DB, document, Document_CPD),
    make_checkpoint_directory(DB, schema, Schema_CPD),
    
    % The version count is one indexed ;D
    N=1,

    % setup schema graph
    interpolate([Schema_CPD,'/',N,'-ckp.ttl'],TTLFile),
    touch(TTLFile),
    interpolate([Schema_CPD,'/',N,'-ckp.hdt'],CKPFile),
    ttl_to_hdt(TTLFile,CKPFile),    

    with_output_graph(
        graph(DB,schema,ckp,ttl),
        (
            interpolate([DB],Label),
            interpolate(['Ontology for ',DB],Comment),
            write_triple(DB,schema,ckp,DB,rdf:type,owl:'Ontology'),
            write_triple(DB,schema,ckp,DB,rdfs:label,literal(lang(en,Label))),
            write_triple(DB,schema,ckp,DB,rdfs:comment,literal(lang(en,Comment)))
        )
    ),

    % setup main graph
    interpolate([Document_CPD,'/',N,'-ckp.ttl'],Document_TTLFile),
    touch(Document_TTLFile),
    interpolate([Document_CPD,'/',N,'-ckp.hdt'],Document_CKPFile),
    ttl_to_hdt(Document_TTLFile,Document_CKPFile),    
    
    sync_from_journals(DB,main),
    sync_from_journals(DB,schema).
    
delete_db(DB) :-
    collection_directory(DB,DB_Path),
    delete_directory_and_contents(DB_Path).

