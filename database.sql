drop table if exists groups;
create table groups (id INTEGER PRIMARY KEY ASC not null,
		    name TEXT not null);
insert into groups (name) VALUES ('ALL');

drop table if exists user;
create table user (id INTEGER PRIMARY KEY ASC not null,
		   name TEXT not null,
		   pass TEXT null);

insert into user (name) VALUES ('admin');


drop table if exists user_sshkeys;
create table user_sshkeys (user_id INTEGER PRIMARY KEY ASC not null,
			   sshkey_id INTEGER);

drop table if exists sshkeys;
create table sshkeys (id INTEGER PRIMARY KEY ASC not null,
		      name TEXT not null,
		      sshkey TEXT not null);

drop table if exists group_members;
create table group_members (group_name TEXT,
			    sshkey_id INTEGER null );

drop table if exists types;
create table types (id INTEGER PRIMARY KEY ASC not null,
		    type TEXT not null);
insert into types (type) VALUES ('USER');
insert into types (type) VALUES ('GROUP');

drop table if exists repo;

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
 

drop table if exists repository;
create table if not exists repository (id INTEGER PRIMARY KEY ASC not null,
                                        name TEXT not null,
                                        description TEXT not null,
                                        is_public INTEGER null,
                                        projectid INTEGER not null,
                                        FOREIGN KEY(projectid) REFERENCES project(id) );

drop view if exists repos;
create view repos AS select project.name as projectname,
							project.id as projectid,
					  project.description as projectdesc,
					  repository.name as reponame,
					  repository.id as repositoryid,
					  repository.description,
					  repository.is_public
				from project LEFT OUTER JOIN repository ON project.id = repository.projectid;
