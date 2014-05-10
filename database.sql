drop table if exists groups;
create table groups (id INTEGER PRIMARY KEY ASC not null,
		    name TEXT not null);
insert into groups (name) VALUES ('ALL');

drop table if exists user;
create table user (id INTEGER PRIMARY KEY ASC not null,
		   name TEXT not null,
		   pass TEXT null);

insert into user (name) VALUES ('git');

drop table if exists sshkeys;
create table sshkeys (id INTEGER PRIMARY KEY ASC not null,
		      sshkey TEXT not null,
		);

drop table if exists group_members;
create table group_members (id INTEGER PRIMARY KEY ASC not null,
			    group_id INTEGER,
			    member_group_id INTEGER null,
			    member_user_id INTEGER null );
insert into group_members (group_id, member_user_id) values (1, 1);

drop table if exists types;
create table types (id INTEGER PRIMARY KEY ASC not null,
		    type TEXT not null);
insert into types (type) VALUES ('USER');
insert into types (type) VALUES ('GROUP');

drop table if exists repo;
create table repo (id INTEGER PRIMARY KEY ASC not null,
		   name TEXT not null );

drop table if exists permissions;
create table permissions (id INTEGER PRIMARY KEY ASC not null,
			  repo_id INT not null,
			  who_id INT,
			  who_type TEXT);

drop table if exists project;
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
