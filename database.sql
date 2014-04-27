create table if not exists user (id INTEGER PRIMARY KEY ASC not null,
                                 user TEXT not null,
                                 pass TEXT not null);

create table if not exists project (id INTEGER PRIMARY KEY ASC not null,
                                    name TEXT not null,
                                    description TEXT not null
                                    );
 

create table if not exists repository (id INTEGER PRIMARY KEY ASC not null,
                                        name TEXT not null,
                                        description TEXT not null,
                                        is_public INTEGER not null,
                                        projectid INTEGER not null,
                                        FOREIGN KEY(projectid) REFERENCES project(id) );
