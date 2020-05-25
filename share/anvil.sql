-- This is the core database schema for the Anvil! Intelligent Availability platform. 
-- 
-- It expects PostgreSQL v. 9.1+
--
-- Table construction rules;
-- 
-- All tables need to have a column called '<table>_uuid  uuid  not null  primary key' that will have a 
-- unique UUID. This is used to keep track of the same entry in the history schema. If the table ends in a
-- plural, the '<table>_uuid' and can use the singular form of the table. For example, the table 'hosts' can
-- use 'host_uuid'.
-- 
-- All tables must hast a 'modified_date  timestamp with time zone  not null' column. This is used to track
-- changes through time in the history schema and used to groups changes when resync'ing.
-- 
-- Tables can optionally have a '*_host_uuid  uuid  not null' colum. If this is found, when resync'ing the
-- table, the resync will be restricted to the host's 'sys::host_uuid'.
-- 
-- Most tables will want to have a matching table in the history schema with an additional 
-- 'history_id  bigserial' column. Match the function and trigger seen elsewhere to copy your data from the
-- public schema to the history schema on UPDATE or INSERT.
-- 
-- If a table is a child of another table, ie: a UPS battery is a child of a UPS, and you have tables for 
-- each that you plan to link, still use a '*_host_uuid' column (if the data is host-specific). This is 
-- needed by the resync method.
-- 
-- NOTE: If you add, rename or remove a table, remember to update the 'sys::database::core_tables' array!
-- 


SET client_encoding = 'UTF8';
-- This doesn't work before 9.3 - CREATE SCHEMA IF NOT EXISTS history;
-- So we'll use the query below until (if) we upgrade.
DO $$
BEGIN
    IF NOT EXISTS(
        SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'history'
    )
    THEN
        EXECUTE 'CREATE SCHEMA history';
    END IF;
END
$$;


-- This stores information about the host machine. This is the master table that everything will be linked 
-- to. 
CREATE TABLE hosts (
    host_uuid        uuid                        not null    primary key,    -- This is the single most important record in Anvil!. Everything links back to here.
    host_name        text                        not null,                   -- This is the 'hostname' of the machine
    host_type        text                        not null,                   -- Either 'node' or 'dashboard' or 'dr'. It is left empty until the host is configured.
    host_key         text                        not null,                   -- This is the host's key used to authenticate it when other machines try to ssh to it.
    host_ipmi        text                        not null    default '',     -- This is an optional string, in 'fence_ipmilan' format, that tells how to access/fence this host.
    modified_date    timestamp with time zone    not null
);
ALTER TABLE hosts OWNER TO admin;

CREATE TABLE history.hosts (
    history_id       bigserial,
    host_uuid        uuid,
    host_name        text,
    host_type        text,
    host_key         text,
    host_ipmi        text,
    modified_date    timestamp with time zone    not null
);
ALTER TABLE history.hosts OWNER TO admin;

CREATE FUNCTION history_hosts() RETURNS trigger
AS $$
DECLARE
    history_hosts RECORD;
BEGIN
    SELECT INTO history_hosts * FROM hosts WHERE host_uuid = new.host_uuid;
    INSERT INTO history.hosts
        (host_uuid, 
         host_name, 
         host_type, 
         host_key, 
         host_ipmi, 
         modified_date)
    VALUES
        (history_hosts.host_uuid,
         history_hosts.host_name,
         history_hosts.host_type,
         history_hosts.host_key, 
         history_hosts.host_ipmi, 
         history_hosts.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_hosts() OWNER TO admin;

CREATE TRIGGER trigger_hosts
    AFTER INSERT OR UPDATE ON hosts
    FOR EACH ROW EXECUTE PROCEDURE history_hosts();


-- This stores the SSH _public_keys for a given user on a host. 
CREATE TABLE host_keys (
    host_key_uuid          uuid                        not null    primary key,    -- This is the single most important record in Anvil!. Everything links back to here.
    host_key_host_uuid     uuid                        not null,
    host_key_user_name     text                        not null,                   -- This is the user name on the system, not a web interface user.
    host_key_public_key    text                        not null,                   -- Either 'node', 'dashboard' or 'dr'
    modified_date          timestamp with time zone    not null, 
    
    FOREIGN KEY(host_key_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE host_keys OWNER TO admin;

CREATE TABLE history.host_keys (
    history_id             bigserial,
    host_key_uuid          uuid,
    host_key_host_uuid     uuid,
    host_key_user_name     text,
    host_key_public_key    text,
    modified_date          timestamp with time zone    not null
);
ALTER TABLE history.host_keys OWNER TO admin;

CREATE FUNCTION history_host_keys() RETURNS trigger
AS $$
DECLARE
    history_host_keys RECORD;
BEGIN
    SELECT INTO history_host_keys * FROM host_keys WHERE host_key_uuid = new.host_key_uuid;
    INSERT INTO history.host_keys
        (host_key_uuid,
         host_key_host_uuid, 
         host_key_user_name, 
         host_key_public_key, 
         modified_date)
    VALUES
        (history_host_keys.host_key_uuid,
         history_host_keys.host_key_host_uuid, 
         history_host_keys.host_key_user_name, 
         history_host_keys.host_key_public_key, 
         history_host_keys.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_host_keys() OWNER TO admin;

CREATE TRIGGER trigger_host_keys
    AFTER INSERT OR UPDATE ON host_keys
    FOR EACH ROW EXECUTE PROCEDURE history_host_keys();


-- This stores information about users. 
-- Note that is all permissions are left false, the user can still interact with the Anvil! doing safe things, like changing optical media, perform migrations, start servers (but not stop them), etc. 
CREATE TABLE users (
    user_uuid              uuid                        not null    primary key,    -- This is the single most important record in Anvil!. Everything links back to here.
    user_name              text                        not null,
    user_password_hash     text                        not null,                   -- A user without a password is disabled.
    user_salt              text                        not null,                   -- This is used to enhance the security of the user's password.
    user_algorithm         text                        not null,                   -- This is the algorithm used to encrypt the password and salt.
    user_hash_count        text                        not null,                   -- This is the number of times that the password+salt was re-hashed through the algorithm.
    user_language          text                        not null,                   -- If set, this will choose a different language over the default.
    user_is_admin          integer                     not null    default 0,      -- If 1, all aspects of the program are available to the user. 
    user_is_experienced    integer                     not null    default 0,      -- If 1, user is allowed to delete a server, alter disk size, alter hardware and do other potentially risky things. They will also get fewer confirmation dialogues. 
    user_is_trusted        integer                     not null    default 0,      -- If 1, user is allowed to do things that would cause interruptions, like force-reset and gracefully stop servers, withdraw nodes, and stop the Anvil! entirely.
    modified_date          timestamp with time zone    not null
);
ALTER TABLE users OWNER TO admin;

CREATE TABLE history.users (
    history_id             bigserial,
    user_uuid              uuid,
    user_name              text,
    user_password_hash     text,
    user_salt              text,
    user_algorithm         text,
    user_hash_count        text,
    user_language          text,
    user_is_admin          integer,
    user_is_experienced    integer,
    user_is_trusted        integer,
    modified_date          timestamp with time zone    not null
);
ALTER TABLE history.users OWNER TO admin;

CREATE FUNCTION history_users() RETURNS trigger
AS $$
DECLARE
    history_users RECORD;
BEGIN
    SELECT INTO history_users * FROM users WHERE user_uuid = new.user_uuid;
    INSERT INTO history.users
        (user_uuid, 
         user_name, 
         user_password_hash, 
         user_salt, 
         user_algorithm, 
         user_hash_count, 
         user_language, 
         user_is_admin, 
         user_is_experienced, 
         user_is_trusted, 
         modified_date)
    VALUES
        (history_users.user_uuid,
         history_users.user_name,
         history_users.user_password_hash, 
         history_users.user_salt, 
         history_users.user_algorithm, 
         history_users.user_hash_count, 
         history_users.user_language, 
         history_users.user_is_admin, 
         history_users.user_is_experienced, 
         history_users.user_is_trusted, 
         history_users.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_users() OWNER TO admin;

CREATE TRIGGER trigger_users
    AFTER INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE PROCEDURE history_users();


-- This stores special variables for a given host that programs may want to record.
CREATE TABLE host_variable (
    host_variable_uuid         uuid                        not null    primary key,    -- This is the single most important record in ScanCore. Everything links back to here.
    host_variable_host_uuid    uuid                        not null,
    host_variable_name         text                        not null,
    host_variable_value        text                        not null,
    modified_date              timestamp with time zone    not null, 
    
    FOREIGN KEY(host_variable_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE host_variable OWNER TO admin;

CREATE TABLE history.host_variable (
    history_id                 bigserial,
    host_variable_uuid         uuid,
    host_variable_host_uuid    uuid,
    host_variable_name         text,
    host_variable_value        text,
    modified_date              timestamp with time zone    not null
);
ALTER TABLE history.host_variable OWNER TO admin;

CREATE FUNCTION history_host_variable() RETURNS trigger
AS $$
DECLARE
    history_host_variable RECORD;
BEGIN
    SELECT INTO history_host_variable * FROM host_variable WHERE host_uuid = new.host_uuid;
    INSERT INTO history.host_variable
        (host_variable_uuid,
         host_variable_host_uuid, 
         host_variable_name, 
         host_variable_value, 
         modified_date)
    VALUES
        (history_host_variable.host_variable_uuid,
         history_host_variable.host_variable_host_uuid, 
         history_host_variable.host_variable_name, 
         history_host_variable.host_variable_value,
         history_host_variable.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_host_variable() OWNER TO admin;

CREATE TRIGGER trigger_host_variable
    AFTER INSERT OR UPDATE ON host_variable
    FOR EACH ROW EXECUTE PROCEDURE history_host_variable();


-- This stores user session information on a per-dashboard basis.
CREATE TABLE sessions (
    session_uuid          uuid                        not null    primary key,    -- This is the single most important record in Anvil!. Everything links back to here.
    session_host_uuid     uuid                        not null,                   -- This is the host uuid for this session.
    session_user_uuid     uuid                        not null,                   -- This is the user uuid for the user logging in.
    session_salt          text                        not null,                   -- This is used when generating a session hash for a session when they log in.
    session_user_agent    text,
    modified_date         timestamp with time zone    not null, 
    
    FOREIGN KEY(session_host_uuid) REFERENCES hosts(host_uuid), 
    FOREIGN KEY(session_user_uuid) REFERENCES users(user_uuid) 
);
ALTER TABLE sessions OWNER TO admin;

CREATE TABLE history.sessions (
    history_id            bigserial, 
    session_uuid          uuid, 
    session_host_uuid     uuid, 
    session_user_uuid     uuid, 
    session_salt          text, 
    session_user_agent    text, 
    modified_date         timestamp with time zone    not null
);
ALTER TABLE history.sessions OWNER TO admin;

CREATE FUNCTION history_sessions() RETURNS trigger
AS $$
DECLARE
    history_sessions RECORD;
BEGIN
    SELECT INTO history_sessions * FROM sessions WHERE session_uuid = new.session_uuid;
    INSERT INTO history.sessions
        (session_uuid, 
         session_host_uuid, 
         session_user_uuid, 
         session_salt, 
         session_user_agent, 
         modified_date)
    VALUES
        (history_sessions.session_uuid,
         history_sessions.session_host_uuid, 
         history_sessions.session_user_uuid, 
         history_sessions.session_salt, 
         history_sessions.session_user_agent, 
         history_sessions.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_sessions() OWNER TO admin;

CREATE TRIGGER trigger_sessions
    AFTER INSERT OR UPDATE ON sessions
    FOR EACH ROW EXECUTE PROCEDURE history_sessions();


-- This stores information about Anvil! systems. 
CREATE TABLE anvils (
    anvil_uuid               uuid                        not null    primary key, 
    anvil_name               text                        not null,
    anvil_description        text                        not null,                -- This is a short, one-line (usually) description of this particular Anvil!. It is displayed in the Anvil! selection list.
    anvil_password           text                        not null,                -- This is the 'hacluster' user password. It is also used to access nodes that don't have a specific password set.
    anvil_node1_host_uuid    uuid,                                                -- This is the host_uuid of the machine that is used as node 1. 
    anvil_node2_host_uuid    uuid,                                                -- This is the host_uuid of the machine that is used as node 2. 
    anvil_dr1_host_uuid      uuid,                                                -- This is the host_uuid of the machine that is used as DR host. 
    modified_date            timestamp with time zone    not null, 
    
    FOREIGN KEY(anvil_node1_host_uuid) REFERENCES hosts(host_uuid), 
    FOREIGN KEY(anvil_node2_host_uuid) REFERENCES hosts(host_uuid), 
    FOREIGN KEY(anvil_dr1_host_uuid) REFERENCES hosts(host_uuid) 
);
ALTER TABLE anvils OWNER TO admin;

CREATE TABLE history.anvils (
    history_id               bigserial,
    anvil_uuid               uuid,
    anvil_name               text,
    anvil_description        text,
    anvil_password           text,
    anvil_node1_host_uuid    uuid,
    anvil_node2_host_uuid    uuid,
    anvil_dr1_host_uuid      uuid,
    modified_date            timestamp with time zone    not null 
);
ALTER TABLE history.anvils OWNER TO admin;

CREATE FUNCTION history_anvils() RETURNS trigger
AS $$
DECLARE
    history_anvils RECORD;
BEGIN
    SELECT INTO history_anvils * FROM anvils WHERE anvil_uuid = new.anvil_uuid;
    INSERT INTO history.anvils
        (anvil_uuid, 
         anvil_name, 
         anvil_description, 
         anvil_password, 
         anvil_node1_host_uuid,
         anvil_node2_host_uuid,
         anvil_dr1_host_uuid,
         modified_date)
    VALUES
        (history_anvils.anvil_uuid, 
         history_anvils.anvil_name, 
         history_anvils.anvil_description, 
         history_anvils.anvil_password, 
         history_anvils.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_anvils() OWNER TO admin;

CREATE TRIGGER trigger_anvils
    AFTER INSERT OR UPDATE ON anvils
    FOR EACH ROW EXECUTE PROCEDURE history_anvils();


-- This stores alerts coming in from various sources
CREATE TABLE alerts (
    alert_uuid             uuid                        not null    primary key,
    alert_host_uuid        uuid                        not null,                    -- The name of the node or dashboard that this alert came from.
    alert_set_by           text                        not null,
    alert_level            integer                     not null,                    -- 1 (critical), 2 (warning), 3 (notice) or 4 (info)
    alert_title            text                        not null,                    -- ScanCore will read in the agents <name>.xml words file and look for this message key
    alert_message          text                        not null,                    -- ScanCore will read in the agents <name>.xml words file and look for this message key
    alert_sort_position    integer                     not null    default 9999,    -- The alerts will sort on this column. It allows for an optional sorting of the messages in the alert.
    alert_show_header      integer                     not null    default 1,       -- This can be set to have the alert be printed with only the contents of the string, no headers.
    modified_date          timestamp with time zone    not null,
    
    FOREIGN KEY(alert_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE alerts OWNER TO admin;

CREATE TABLE history.alerts (
    history_id             bigserial,
    alert_uuid             uuid,
    alert_host_uuid        uuid,
    alert_set_by           text,
    alert_level            integer,
    alert_title            text,
    alert_message          text,
    alert_sort_position    integer,
    alert_show_header      integer,
    modified_date          timestamp with time zone    not null
);
ALTER TABLE history.alerts OWNER TO admin;

CREATE FUNCTION history_alerts() RETURNS trigger
AS $$
DECLARE
    history_alerts RECORD;
BEGIN
    SELECT INTO history_alerts * FROM alerts WHERE alert_uuid = new.alert_uuid;
    INSERT INTO history.alerts
        (alert_uuid,
         alert_host_uuid,
         alert_set_by,
         alert_level,
         alert_title,
         alert_message,
         alert_sort_position, 
         alert_show_header, 
         modified_date)
    VALUES
        (history_alerts.alert_uuid,
         history_alerts.alert_host_uuid,
         history_alerts.alert_set_by,
         history_alerts.alert_level,
         history_alerts.alert_title,
         history_alerts.alert_message,
         history_alerts.alert_sort_position, 
         history_alerts.alert_show_header, 
         history_alerts.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_alerts() OWNER TO admin;

CREATE TRIGGER trigger_alerts
    AFTER INSERT OR UPDATE ON alerts
    FOR EACH ROW EXECUTE PROCEDURE history_alerts();

    
-- NOTE: This doesn't store the user's level, as it might be unique per Anvil!.
-- This is the list of alert recipients.
CREATE TABLE recipients (
    recipient_uuid         uuid                        not null    primary key,
    recipient_name         text                        not null,                    -- This is the recipient's name
    recipient_email        text                        not null,                    -- This is the recipient's email address or the file name, depending.
    recipient_language     text                        not null,                    -- If set, this is the language the user wants to receive alerts in. If not set, the default language is used.
    recipient_units        text                        not null,                    -- This can be set to 'imperial' if the user prefers temperatures in °F
    recipient_new_level    integer                     not null,                    -- This is the alert level to use when automatically adding watch links to new systems. '0' tells us to ignore new systems, 1 is critical, 2 is warning, and 3 is notice
    modified_date          timestamp with time zone    not null
);
ALTER TABLE recipients OWNER TO admin;

CREATE TABLE history.recipients (
    history_id             bigserial,
    recipient_uuid         uuid,
    recipient_name         text,
    recipient_email        text,
    recipient_language     text,
    recipient_units        text,
    recipient_new_level    integer,
    modified_date          timestamp with time zone    not null
);
ALTER TABLE history.recipients OWNER TO admin;

CREATE FUNCTION history_recipients() RETURNS trigger
AS $$
DECLARE
    history_recipients RECORD;
BEGIN
    SELECT INTO history_recipients * FROM recipients WHERE recipient_uuid = new.recipient_uuid;
    INSERT INTO history.recipients
        (recipient_uuid,
         recipient_name,
         recipient_email,
         recipient_language,
         recipient_units, 
         recipient_new_level,
         modified_date)
    VALUES
        (history_recipients.recipient_uuid,
         history_recipients.recipient_name,
         history_recipients.recipient_email,
         history_recipients.recipient_language,
         history_recipients.recipient_units,
         history_recipients.recipient_new_level,
         history_recipients.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_recipients() OWNER TO admin;

CREATE TRIGGER trigger_recipients
    AFTER INSERT OR UPDATE ON recipients
    FOR EACH ROW EXECUTE PROCEDURE history_recipients();


-- This creates links between recipients and Anvil! systems, with a request alert level, so that we can 
-- decide who gets what alerts for a given Anvil! system
CREATE TABLE notifications (
    notification_uuid              uuid                        not null    primary key,
    notification_recipient_uuid    uuid                        not null,                    -- The recipient we're linking.
    notification_host_uuid         uuid                        not null,                    -- This host_uuid of the referenced machine
    notification_alert_level       integer                     not null,                    -- This is the alert level (at or above) that this user wants alerts from.
    modified_date                  timestamp with time zone    not null,
    
    FOREIGN KEY(notification_host_uuid)     REFERENCES anvils(anvil_uuid),
    FOREIGN KEY(notification_recipient_uuid) REFERENCES recipients(recipient_uuid)
);
ALTER TABLE notifications OWNER TO admin;

CREATE TABLE history.notifications (
    history_id                     bigserial,
    notification_uuid              uuid,
    notification_recipient_uuid    uuid,
    notification_host_uuid        uuid,
    notification_alert_level       integer,
    modified_date                  timestamp with time zone    not null
);
ALTER TABLE history.notifications OWNER TO admin;

CREATE FUNCTION history_notifications() RETURNS trigger
AS $$
DECLARE
    history_notifications RECORD;
BEGIN
    SELECT INTO history_notifications * FROM notifications WHERE notification_uuid = new.notification_uuid;
    INSERT INTO history.notifications
        (notification_uuid, 
         notification_recipient_uuid, 
         notification_host_uuid, 
         notification_alert_level, 
         modified_date)
    VALUES
        (history_notifications.notification_uuid,
         history_notifications.notification_recipient_uuid, 
         history_notifications.notification_host_uuid, 
         history_notifications.notification_alert_level, 
         history_notifications.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_notifications() OWNER TO admin;

CREATE TRIGGER trigger_notifications
    AFTER INSERT OR UPDATE ON notifications
    FOR EACH ROW EXECUTE PROCEDURE history_notifications();


-- This creates a list of mail servers that are available for use by hosts. This information is used to 
-- configure postfix on the host.
CREATE TABLE mail_servers (
    mail_server_uuid              uuid                        not null    primary key,
    mail_server_address           text                        not null,                   -- example; mail.example.com
    mail_server_port              integer                     not null,                   -- The TCP port used to connect to the server.
    mail_server_username          text                        not null,                   -- This is the user name (usually email address) used when authenticating against the mail server.
    mail_server_password          text                        not null,                   -- This is the password used when authenticating against the mail server
    mail_server_security          text                        not null,                   -- This is the security type used when authenticating against the mail server (STARTTLS, TLS/SSL or NONE)
    mail_server_authentication    text                        not null,                   -- 'None', 'Plain Text', 'Encrypted'.
    mail_server_helo_domain       text                        not null,                   -- The domain we identify to the mail server as being from. The default is to use the domain name of the host.
    modified_date                 timestamp with time zone    not null
);
ALTER TABLE mail_servers OWNER TO admin;

CREATE TABLE history.mail_servers (
    history_id                    bigserial,
    mail_server_uuid              uuid,
    mail_server_address           text,
    mail_server_port              integer,
    mail_server_username          text,
    mail_server_password          text,
    mail_server_security          text,
    mail_server_authentication    text,
    mail_server_helo_domain       text,
    modified_date                 timestamp with time zone    not null
);
ALTER TABLE history.mail_servers OWNER TO admin;

CREATE FUNCTION history_mail_servers() RETURNS trigger
AS $$
DECLARE
    history_mail_servers RECORD;
BEGIN
    SELECT INTO history_mail_servers * FROM mail_servers WHERE mail_server_uuid = new.mail_server_uuid;
    INSERT INTO history.mail_servers
        (mail_server_uuid, 
         mail_server_address, 
         mail_server_port, 
         mail_server_username, 
         mail_server_password, 
         mail_server_security, 
         mail_server_authentication, 
         mail_server_helo_domain, 
         modified_date)
    VALUES
        (history_mail_servers.mail_server_uuid,
         history_mail_servers.mail_server_address, 
         history_mail_servers.mail_server_port, 
         history_mail_servers.mail_server_username, 
         history_mail_servers.mail_server_password, 
         history_mail_servers.mail_server_security, 
         history_mail_servers.mail_server_authentication, 
         history_mail_servers.mail_server_helo_domain, 
         history_mail_servers.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_mail_servers() OWNER TO admin;

CREATE TRIGGER trigger_mail_servers
    AFTER INSERT OR UPDATE ON mail_servers
    FOR EACH ROW EXECUTE PROCEDURE history_mail_servers();


-- This holds user-configurable variable. These values override defaults but NOT configuration files.
CREATE TABLE variables (
    variable_uuid            uuid                        not null    primary key,
    variable_name            text                        not null,                   -- This is the 'x::y::z' style variable name.
    variable_value           text                        not null,                   -- It is up to the software to sanity check variable values before they are stored
    variable_default         text                        not null,                   -- This acts as a reference for the user should they want to roll-back changes.
    variable_description     text                        not null,                   -- This is a string key that describes this variable's use.
    variable_section         text                        not null,                   -- This is a free-form field that is used when displaying the various entries to a user. This allows for the various variables to be grouped into sections.
    variable_source_uuid     text                        not null,                   -- Optional; Marks the variable as belonging to a specific X_uuid, where 'X' is a table name set in 'variable_source_table'
    variable_source_table    text                        not null,                   -- Optional; Marks the database table corresponding to the 'variable_source_uuid' value.
    modified_date            timestamp with time zone    not null 
);
ALTER TABLE variables OWNER TO admin;

CREATE TABLE history.variables (
    history_id               bigserial,
    variable_uuid            uuid,
    variable_name            text,
    variable_value           text,
    variable_default         text,
    variable_description     text,
    variable_section         text,
    variable_source_uuid     text,
    variable_source_table    text,
    modified_date            timestamp with time zone    not null 
);
ALTER TABLE history.variables OWNER TO admin;

CREATE FUNCTION history_variables() RETURNS trigger
AS $$
DECLARE
    history_variables RECORD;
BEGIN
    SELECT INTO history_variables * FROM variables WHERE variable_uuid = new.variable_uuid;
    INSERT INTO history.variables
        (variable_uuid,
         variable_name, 
         variable_value, 
         variable_default, 
         variable_description, 
         variable_section, 
         variable_source_uuid, 
         variable_source_table, 
         modified_date)
    VALUES
        (history_variables.variable_uuid,
         history_variables.variable_name, 
         history_variables.variable_value, 
         history_variables.variable_default, 
         history_variables.variable_description, 
         history_variables.variable_section, 
         history_variables.variable_source_uuid, 
         history_variables.variable_source_table, 
         history_variables.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_variables() OWNER TO admin;

CREATE TRIGGER trigger_variables
    AFTER INSERT OR UPDATE ON variables
    FOR EACH ROW EXECUTE PROCEDURE history_variables();


-- This holds jobs to be run.
CREATE TABLE jobs (
    job_uuid           uuid                        not null    primary key,    -- 
    job_host_uuid      uuid                        not null,                   -- This is the host that requested the job
    job_command        text                        not null,                   -- This is the command to run (usually a shell call).
    job_data           text                        not null,                   -- A job can optionally use this to store miscellaneous data that doesn't belong elsewhere
    job_picked_up_by   numeric                     not null    default 0,      -- This is the PID of the 'anvil-jobs' script that picked up the job.
    job_picked_up_at   numeric                     not null    default 0,      -- This is unix timestamp of when the job was picked up.
    job_updated        numeric                     not null    default 0,      -- This is unix timestamp that is perdiodically updated for jobs that take a long time. It is used to help determine when a job is hung.
    job_name           text                        not null,                   -- This is the 'x::y::z' style job name.
    job_progress       numeric                     not null    default 0,      -- An approximate percentage completed. Useful for jobs that that a while and are able to provide data for progress bars. When set to '100', the job is considered completed.
    job_title          text                        not null,                   -- This is a word key for the title of this job
    job_description    text                        not null,                   -- This is a word key that describes this job.
    job_status         text,                                                   -- This is a field used to report the status of the job. It is expected to be 'key,!!var1!foo!!,...,!!varN!bar!!' format, one per line. If the last line is 'failed', the job will be understood to have failed.
    modified_date      timestamp with time zone    not null,
    
    FOREIGN KEY(job_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE jobs OWNER TO admin;

CREATE TABLE history.jobs (
    history_id         bigserial,
    job_uuid           uuid,
    job_host_uuid      uuid,
    job_command        text,
    job_data           text,
    job_picked_up_by   numeric,
    job_picked_up_at   numeric,
    job_updated        numeric,
    job_name           text,
    job_progress       numeric,
    job_title          text,
    job_description    text,
    job_status         text,
    modified_date      timestamp with time zone    not null 
);
ALTER TABLE history.jobs OWNER TO admin;

CREATE FUNCTION history_jobs() RETURNS trigger
AS $$
DECLARE
    history_jobs RECORD;
BEGIN
    SELECT INTO history_jobs * FROM jobs WHERE job_uuid = new.job_uuid;
    INSERT INTO history.jobs
        (job_uuid, 
         job_host_uuid, 
         job_command, 
         job_data, 
         job_picked_up_by, 
         job_picked_up_at, 
         job_updated, 
         job_name, 
         job_progress, 
         job_title, 
         job_description, 
         job_status, 
         modified_date)
    VALUES
        (history_jobs.job_uuid,
         history_jobs.job_host_uuid, 
         history_jobs.job_command, 
         history_jobs.job_data, 
         history_jobs.job_picked_up_by, 
         history_jobs.job_picked_up_at, 
         history_jobs.job_updated, 
         history_jobs.job_name, 
         history_jobs.job_progress, 
         history_jobs.job_title, 
         history_jobs.job_description, 
         history_jobs.job_status, 
         history_jobs.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_jobs() OWNER TO admin;

CREATE TRIGGER trigger_jobs
    AFTER INSERT OR UPDATE ON jobs
    FOR EACH ROW EXECUTE PROCEDURE history_jobs();


-- This stores information about network bridges. 
CREATE TABLE bridges (
    bridge_uuid           uuid                        not null    primary key,
    bridge_host_uuid      uuid                        not null,
    bridge_name           text                        not null,
    bridge_id             text                        not null,
    bridge_mac_address    text                        not null,
    bridge_mtu            text                        not null,
    bridge_stp_enabled    text                        not null,                  -- 0 = disabled, 1 = kernel STP, 2 = user STP
    modified_date         timestamp with time zone    not null,
    
    FOREIGN KEY(bridge_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE bridges OWNER TO admin;

CREATE TABLE history.bridges (
    history_id            bigserial,
    bridge_uuid           uuid,
    bridge_host_uuid      uuid,
    bridge_name           text,
    bridge_id             text,
    bridge_mac_address    text,
    bridge_mtu            text,
    bridge_stp_enabled    text,
    modified_date         timestamp with time zone    not null
);
ALTER TABLE history.bridges OWNER TO admin;

CREATE FUNCTION history_bridges() RETURNS trigger
AS $$
DECLARE
    history_bridges RECORD;
BEGIN
    SELECT INTO history_bridges * FROM bridges WHERE bridge_uuid = new.bridge_uuid;
    INSERT INTO history.bridges
        (bridge_uuid, 
         bridge_host_uuid, 
         bridge_name, 
         bridge_id, 
         bridge_mac_address, 
         bridge_mtu, 
         bridge_stp_enabled, 
         modified_date)
    VALUES
        (history_bridges.bridge_uuid, 
         history_bridges.bridge_host_uuid, 
         history_bridges.bridge_name, 
         history_bridges.bridge_id, 
         history_bridges.bridge_mac_address, 
         history_bridges.bridge_mtu, 
         history_bridges.bridge_stp_enabled, 
         history_bridges.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_bridges() OWNER TO admin;

CREATE TRIGGER trigger_bridges
    AFTER INSERT OR UPDATE ON bridges
    FOR EACH ROW EXECUTE PROCEDURE history_bridges();


-- This stores information about network bonds (mode=1) on a hosts.
CREATE TABLE bonds (
    bond_uuid                    uuid                        not null    primary key,
    bond_host_uuid               uuid                        not null,
    bond_name                    text                        not null,
    bond_mode                    text                        not null,                   -- This is the numerical bond type (will translate to the user's language in the Anvil!)
    bond_mtu                     bigint                      not null,
    bond_primary_interface       text                        not null,
    bond_primary_reselect        text                        not null,
    bond_active_interface        text                        not null,
    bond_mii_polling_interval    bigint                      not null,
    bond_up_delay                bigint                      not null,
    bond_down_delay              bigint                      not null,
    bond_mac_address             text                        not null,
    bond_operational             text                        not null,                   -- This is 'up', 'down' or 'unknown' 
    bond_bridge_uuid             uuid,
    modified_date                timestamp with time zone    not null,
    
    FOREIGN KEY(bond_bridge_uuid) REFERENCES bridges(bridge_uuid),
    FOREIGN KEY(bond_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE bonds OWNER TO admin;

CREATE TABLE history.bonds (
    history_id                   bigserial,
    bond_uuid                    uuid,
    bond_host_uuid               uuid,
    bond_name                    text,
    bond_mode                    text,
    bond_mtu                     bigint,
    bond_primary_interface       text,
    bond_primary_reselect        text,
    bond_active_interface        text,
    bond_mii_polling_interval    bigint,
    bond_up_delay                bigint,
    bond_down_delay              bigint,
    bond_mac_address             text, 
    bond_operational             text,
    bond_bridge_uuid             uuid,
    modified_date                timestamp with time zone    not null
);
ALTER TABLE history.bonds OWNER TO admin;

CREATE FUNCTION history_bonds() RETURNS trigger
AS $$
DECLARE
    history_bonds RECORD;
BEGIN
    SELECT INTO history_bonds * FROM bonds WHERE bond_uuid = new.bond_uuid;
    INSERT INTO history.bonds
        (bond_uuid,
         bond_host_uuid,
         bond_name, 
         bond_mode, 
         bond_mtu, 
         bond_primary_interface, 
         bond_primary_reselect, 
         bond_active_interface, 
         bond_mii_polling_interval, 
         bond_up_delay, 
         bond_down_delay, 
         bond_mac_address, 
         bond_operational, 
         bond_bridge_uuid, 
         modified_date)
    VALUES
        (history_bonds.bond_uuid,
         history_bonds.bond_host_uuid,
         history_bonds.bond_name, 
         history_bonds.bond_mode, 
         history_bonds.bond_mtu, 
         history_bonds.bond_primary_interface, 
         history_bonds.bond_primary_reselect, 
         history_bonds.bond_active_interface, 
         history_bonds.bond_mii_polling_interval, 
         history_bonds.bond_up_delay, 
         history_bonds.bond_down_delay, 
         history_bonds.bond_mac_address, 
         history_bonds.bond_operational, 
         history_bonds.bond_bridge_uuid, 
         history_bonds.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_bonds() OWNER TO admin;

CREATE TRIGGER trigger_bonds
    AFTER INSERT OR UPDATE ON bonds
    FOR EACH ROW EXECUTE PROCEDURE history_bonds();


-- This stores information about network interfaces on hosts. It is mainly used to match a MAC address to a
-- host. Given that it is possible that network devices can move, the linkage to the host_uuid can change.
CREATE TABLE network_interfaces (
    network_interface_uuid           uuid                        not null    primary key,
    network_interface_host_uuid      uuid                        not null,
    network_interface_mac_address    text                        not null,
    network_interface_name           text                        not null,                   -- This is the current name of the interface. 
    network_interface_speed          bigint                      not null,                   -- This is the speed, in bits-per-second, of the interface.
    network_interface_mtu            bigint                      not null,                   -- This is the MTU (Maximum Transmitable Size), in bytes, for this interface.
    network_interface_link_state     text                        not null,                   -- 0 or 1
    network_interface_operational    text                        not null,                   -- This is 'up', 'down' or 'unknown' 
    network_interface_duplex         text                        not null,                   -- This is 'full', 'half' or 'unknown' 
    network_interface_medium         text                        not null,                   -- This is 'tp' (twisted pair), 'fiber' or whatever they invent in the future.
    network_interface_bond_uuid      uuid,                                                   -- If this iface is in a bond, this will contain the 'bonds -> bond_uuid' that it is slaved to.
    network_interface_bridge_uuid    uuid,                                                   -- If this iface is attached to a bridge, this will contain the 'bridgess -> bridge_uuid' that it is connected to.
    modified_date                    timestamp with time zone    not null, 
    
    FOREIGN KEY(network_interface_bridge_uuid) REFERENCES bridges(bridge_uuid),
    FOREIGN KEY(network_interface_bond_uuid) REFERENCES bonds(bond_uuid),
    FOREIGN KEY(network_interface_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE network_interfaces OWNER TO admin;

CREATE TABLE history.network_interfaces (
    history_id                       bigserial,
    network_interface_uuid           uuid                        not null,
    network_interface_host_uuid      uuid,
    network_interface_mac_address    text,
    network_interface_name           text,
    network_interface_speed          bigint,
    network_interface_mtu            bigint,
    network_interface_link_state     text,
    network_interface_operational    text,
    network_interface_duplex         text,
    network_interface_medium         text,
    network_interface_bond_uuid      uuid,
    network_interface_bridge_uuid    uuid,
    modified_date                    timestamp with time zone    not null
);
ALTER TABLE history.network_interfaces OWNER TO admin;

CREATE FUNCTION history_network_interfaces() RETURNS trigger
AS $$
DECLARE
    history_network_interfaces RECORD;
BEGIN
    SELECT INTO history_network_interfaces * FROM network_interfaces WHERE network_interface_uuid = new.network_interface_uuid;
    INSERT INTO history.network_interfaces
        (network_interface_uuid,
         network_interface_host_uuid, 
         network_interface_mac_address, 
         network_interface_name,
         network_interface_speed, 
         network_interface_mtu, 
         network_interface_link_state, 
         network_interface_operational, 
         network_interface_duplex, 
         network_interface_medium, 
         network_interface_bond_uuid, 
         network_interface_bridge_uuid, 
         modified_date)
    VALUES
        (history_network_interfaces.network_interface_uuid,
         history_network_interfaces.network_interface_host_uuid, 
         history_network_interfaces.network_interface_mac_address, 
         history_network_interfaces.network_interface_name,
         history_network_interfaces.network_interface_speed, 
         history_network_interfaces.network_interface_mtu, 
         history_network_interfaces.network_interface_link_state, 
         history_network_interfaces.network_interface_operational, 
         history_network_interfaces.network_interface_duplex, 
         history_network_interfaces.network_interface_medium, 
         history_network_interfaces.network_interface_bond_uuid, 
         history_network_interfaces.network_interface_bridge_uuid, 
         history_network_interfaces.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_network_interfaces() OWNER TO admin;

CREATE TRIGGER trigger_network_interfaces
    AFTER INSERT OR UPDATE ON network_interfaces
    FOR EACH ROW EXECUTE PROCEDURE history_network_interfaces();


-- This stores information about network ip addresss. 
CREATE TABLE ip_addresses (
    ip_address_uuid               uuid                        not null    primary key,
    ip_address_host_uuid          uuid                        not null,
    ip_address_on_type            text                        not null,                     -- Either 'interface', 'bond' or 'bridge'
    ip_address_on_uuid            uuid                        not null,                     -- This is the UUID of the interface, bond or bridge that has this IP
    ip_address_address            text                        not null,                     -- The actual IP address
    ip_address_subnet_mask        text                        not null,                     -- The subnet mask (in dotted decimal format)
    ip_address_gateway            text                        not null,                     -- If set, this is the gateway IP for this subnet
    ip_address_default_gateway    integer                     not null    default 0,        -- If true, the gateway will be the default for the host.
    ip_address_dns                text                        not null,                     -- If set, this is a comma-separated list of DNS IPs to use (in the order given)
    ip_address_note               text                        not null,                     -- Set to 'DELETED' when no longer in use.
    modified_date                 timestamp with time zone    not null,
    
    FOREIGN KEY(ip_address_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE ip_addresses OWNER TO admin;

CREATE TABLE history.ip_addresses (
    history_id                    bigserial,
    ip_address_uuid               uuid,
    ip_address_host_uuid          uuid,
    ip_address_on_type            text,
    ip_address_on_uuid            uuid,
    ip_address_address            text,
    ip_address_subnet_mask        text,
    ip_address_gateway            text,
    ip_address_default_gateway    integer,
    ip_address_dns                text,
    ip_address_note               text,
    modified_date                 timestamp with time zone    not null
);
ALTER TABLE history.ip_addresses OWNER TO admin;

CREATE FUNCTION history_ip_addresses() RETURNS trigger
AS $$
DECLARE
    history_ip_addresses RECORD;
BEGIN
    SELECT INTO history_ip_addresses * FROM ip_addresses WHERE ip_address_uuid = new.ip_address_uuid;
    INSERT INTO history.ip_addresses
        (ip_address_uuid, 
         ip_address_host_uuid, 
         ip_address_on_type, 
         ip_address_on_uuid, 
         ip_address_address, 
         ip_address_subnet_mask, 
         ip_address_gateway, 
         ip_address_default_gateway, 
         ip_address_dns, 
         ip_address_note, 
         modified_date)
    VALUES
        (history_ip_addresses.ip_address_uuid, 
         history_ip_addresses.ip_address_host_uuid, 
         history_ip_addresses.ip_address_on_type, 
         history_ip_addresses.ip_address_on_uuid, 
         history_ip_addresses.ip_address_address, 
         history_ip_addresses.ip_address_subnet_mask, 
         history_ip_addresses.ip_address_gateway, 
         history_ip_addresses.ip_address_default_gateway, 
         history_ip_addresses.ip_address_note, 
         history_ip_addresses.ip_address_dns, 
         history_ip_addresses.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_ip_addresses() OWNER TO admin;

CREATE TRIGGER trigger_ip_addresses
    AFTER INSERT OR UPDATE ON ip_addresses
    FOR EACH ROW EXECUTE PROCEDURE history_ip_addresses();


-- This stores files made available to Anvil! systems and DR hosts.
CREATE TABLE files (
    file_uuid        uuid                        not null    primary key,
    file_name        text                        not null,                   -- This is the file's name. It can change without re-uploading the file.
    file_directory   text                        not null,                   -- This is the directory that the file is in.
    file_size        numeric                     not null,                   -- This is the file's size in bytes. If it recorded as a quick way to determine if a file has changed on disk.
    file_md5sum      text                        not null,                   -- This is the sum as calculated when the file is first uploaded. Once recorded, it can't change.
    file_type        text                        not null,                   -- This is the file's type/purpose. The expected values are 'iso', 'rpm', 'script', 'disk-image', or 'other'. 
    file_mtime       numeric                     not null,                   -- If the same file exists on different machines and differ md5sums/sizes, the one with the most recent mtime will be used to update the others.
    modified_date    timestamp with time zone    not null
);
ALTER TABLE files OWNER TO admin;

CREATE TABLE history.files (
    history_id       bigserial,
    file_uuid        uuid,
    file_name        text,
    file_directory   text, 
    file_size        numeric,
    file_md5sum      text,
    file_type        text,
    file_mtime       numeric,
    modified_date    timestamp with time zone    not null
);
ALTER TABLE history.files OWNER TO admin;

CREATE FUNCTION history_files() RETURNS trigger
AS $$
DECLARE
    history_files RECORD;
BEGIN
    SELECT INTO history_files * FROM files WHERE file_uuid = new.file_uuid;
    INSERT INTO history.files
        (file_uuid,
         file_name, 
         file_directory, 
         file_size, 
         file_md5sum, 
         file_type, 
         file_mtime, 
         modified_date)
    VALUES
        (history_files.file_uuid, 
         history_files.file_name, 
         history_files.file_directory, 
         history_files.file_size, 
         history_files.file_md5sum, 
         history_files.file_type, 
         history_files.file_mtime, 
         history_files.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_files() OWNER TO admin;

CREATE TRIGGER trigger_files
    AFTER INSERT OR UPDATE ON files
    FOR EACH ROW EXECUTE PROCEDURE history_files();


-- NOTE: When an entry is made here, the next time files are checked on a machine and an entry doesn't exist 
--       on disk, the file fill be found (if possible) and copied to the houst. Only machines on the same 
--       subnet are searched. Of course, if a URL is given (or a file is uploaded over a browser), the file
--       will be sourced accordingly. The search pattern is; 
--       Nodes;   1. Check for the file on the peer.
--                2. Check for the file on Strikers, in alphabetical order.
--                3. Check for the file on DR host, if available.
--                4. Check other nodes, in alphabetical order.
--                5. Check other DR hosts, in alphabetical order.
--       Striker; 1. Check for the file on other Strikers, in alphabetical order.
--                2. Check for the file on DR hosts, if available
--                3. Check for the file on Anvil! nodes.
--       DR Host; 1. Check for the file on Strikers, in alphabetical order.
--                2. Check for the file on Anvil! nodes.
--       * If a file can't be found, it will try again every so often until it is found.
--       * When a file is found, it is copied to '/mnt/shared/incoming'. Only when the file has arrived and 
--         the md5sum matches. At this point, it is moved into the proper directory.
--       How new files are handled;
--       * When uploading a file from a Striker web interface, or when creating an ISO from physical media,
--         it will be dropped into /mnt/shared/incoming. Once there, the user will have the option of pushing
--         the file to an Anvil! system. ISOs and scripts will go to both nodes (and the DR host, when 
--         needed).
--       * Repo RPMs are sync'ed to all peer'ed dashboards, but not sent to hosts (they are used during the
--         initial host setup).
--       * Special Note: Definition files are stored in the database and written out as needed to the 
--                       nodes/DR host.
--       
-- This tracks which files should be on which machines.
CREATE TABLE file_locations (
    file_location_uuid         uuid                        not null    primary key,
    file_location_file_uuid    uuid                        not null,                   -- This is file to be moved to (or restored to) this machine.
    file_location_host_uuid    uuid                        not null,                   -- This is the sum as calculated when the file_location is first uploaded. Once recorded, it can't change.
    modified_date              timestamp with time zone    not null,
    
    FOREIGN KEY(file_location_file_uuid) REFERENCES files(file_uuid), 
    FOREIGN KEY(file_location_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE file_locations OWNER TO admin;

CREATE TABLE history.file_locations (
    history_id                 bigserial,
    file_location_uuid         uuid,
    file_location_file_uuid    text,
    file_location_host_uuid    text,
    modified_date              timestamp with time zone    not null
);
ALTER TABLE history.file_locations OWNER TO admin;

CREATE FUNCTION history_file_locations() RETURNS trigger
AS $$
DECLARE
    history_file_locations RECORD;
BEGIN
    SELECT INTO history_file_locations * FROM file_locations WHERE file_location_uuid = new.file_location_uuid;
    INSERT INTO history.file_locations
        (file_location_uuid,
         file_location_file_uuid,
         file_location_host_uuid, 
         modified_date)
    VALUES
        (history_file_locations.file_location_uuid, 
         history_file_locations.file_location_file_uuid,
         history_file_locations.file_location_host_uuid, 
         history_file_locations.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_file_locations() OWNER TO admin;

CREATE TRIGGER trigger_file_locations
    AFTER INSERT OR UPDATE ON file_locations
    FOR EACH ROW EXECUTE PROCEDURE history_file_locations();


-- This stores servers made available to Anvil! systems and DR hosts.
CREATE TABLE servers (
    server_uuid                        uuid                        not null    primary key,
    server_name                        text                        not null,                     -- This is the server's name. It can change without re-uploading the server.
    server_anvil_uuid                  uuid                        not null,                     -- This is the Anvil! system that the server lives on. It can move to another Anvil!, so this can change.
    server_clean_stop                  boolean                                 default FALSE,    -- When set, the server was stopped by a user. The Anvil! will not start a server that has been cleanly stopped.
    server_start_after_server_uuid     uuid,                                                     -- This can be the server_uuid of another server. If set, this server will boot 'server_start_delay' seconds after the referenced server boots. A value of '00000000-0000-0000-0000-000000000000' will tell 'anvil-safe-start' to not boot the server at all. If a server is set not to start, any dependent servers will also stay off.
    server_start_delay                 integer                     not null    default 0,        -- See above.
    server_host_uuid                   uuid,                                                     -- This is the current hosts -> host_uuid for this server. If the server is off, this will be blank.
    server_state                       text,                                                     -- This is the current state of this server.
    server_live_migration              boolean                     not null    default TRUE,     -- When false, servers will be stopped and then rebooted when a migration is requested. Also, when false, preventative migrations will not happen.
    server_pre_migration_file_uuid     uuid,                                                     -- This is set to the files -> file_uuid of a script to run BEFORE migrating a server. If the file isn't found or can't run, the script is ignored.
    server_pre_migration_arguments     text,                                                     -- These are arguments to pass to the pre-migration script
    server_post_migration_file_uuid    uuid,                                                     -- This is set to the files -> file_uuid of a script to run AFTER migrating a server. If the file isn't found or can't run, the script is ignored.
    server_post_migration_arguments    text,                                                     -- These are arguments to pass to the post-migration script
    modified_date                      timestamp with time zone    not null, 
    
    FOREIGN KEY(server_anvil_uuid)               REFERENCES anvils(anvil_uuid),
    FOREIGN KEY(server_start_after_server_uuid)  REFERENCES servers(server_uuid),
    FOREIGN KEY(server_host_uuid)                REFERENCES hosts(host_uuid), 
    FOREIGN KEY(server_pre_migration_file_uuid)  REFERENCES files(file_uuid), 
    FOREIGN KEY(server_post_migration_file_uuid) REFERENCES files(file_uuid) 
);
ALTER TABLE servers OWNER TO admin;

CREATE TABLE history.servers (
    history_id                         bigserial,
    server_uuid                        uuid,
    server_name                        text,
    server_anvil_uuid                  uuid,
    server_clean_stop                  boolean,
    server_start_after_server_uuid     uuid,
    server_start_delay                 integer,
    server_host_uuid                   uuid,
    server_state                       text,
    server_live_migration              boolean,
    server_pre_migration_file_uuid     uuid,
    server_pre_migration_arguments     text,
    server_post_migration_file_uuid    uuid,
    server_post_migration_arguments    text,
    modified_date                      timestamp with time zone    not null
);
ALTER TABLE history.servers OWNER TO admin;

CREATE FUNCTION history_servers() RETURNS trigger
AS $$
DECLARE
    history_servers RECORD;
BEGIN
    SELECT INTO history_servers * FROM servers WHERE server_uuid = new.server_uuid;
    INSERT INTO history.servers
        (server_uuid,
         server_name, 
         server_anvil_uuid,
         server_clean_stop,
         server_start_after_server_uuid,
         server_start_delay,
         server_host_uuid,
         server_state,
         server_live_migration,
         server_pre_migration_file_uuid,
         server_pre_migration_arguments,
         server_post_migration_file_uuid,
         server_post_migration_arguments,
         modified_date)
    VALUES
        (history_servers.server_uuid, 
         history_servers.server_name, 
         history_servers.server_clean_stop,
         history_servers.server_start_after_server_uuid,
         history_servers.server_start_delay,
         history_servers.server_host_uuid,
         history_servers.server_state,
         history_servers.server_live_migration,
         history_servers.server_pre_migration_file_uuid,
         history_servers.server_pre_migration_arguments,
         history_servers.server_post_migration_file_uuid,
         history_servers.server_post_migration_arguments,
         history_servers.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_servers() OWNER TO admin;

CREATE TRIGGER trigger_servers
    AFTER INSERT OR UPDATE ON servers
    FOR EACH ROW EXECUTE PROCEDURE history_servers();


-- This stores the XML definition for a server. Whenever a definition is found missing on a node or DR host, 
-- it will be rewritten from here. If this copy changes, it will be updated on the hosts.
CREATE TABLE definitions (
    definition_uuid           uuid                        not null    primary key,
    definition_server_uuid    uuid                        not null,                   -- This is the servers -> server_uuid of the server
    definition_xml            text                        not null,                   -- This is the XML body.
    modified_date             timestamp with time zone    not null, 
    
    FOREIGN KEY(definition_server_uuid) REFERENCES servers(server_uuid) 
);
ALTER TABLE definitions OWNER TO admin;

CREATE TABLE history.definitions (
    history_id                bigserial,
    definition_uuid           uuid,
    definition_server_uuid    uuid, 
    definition_xml            text, 
    modified_date             timestamp with time zone    not null
);
ALTER TABLE history.definitions OWNER TO admin;

CREATE FUNCTION history_definitions() RETURNS trigger
AS $$
DECLARE
    history_definitions RECORD;
BEGIN
    SELECT INTO history_definitions * FROM definitions WHERE definition_uuid = new.definition_uuid;
    INSERT INTO history.definitions
        (definition_uuid,
         definition_server_uuid, 
         definition_xml, 
         modified_date)
    VALUES
        (history_definitions.definition_uuid, 
         history_definitions.definition_server_uuid, 
         history_definitions.definition_xml, 
         history_definitions.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_definitions() OWNER TO admin;

CREATE TRIGGER trigger_definitions
    AFTER INSERT OR UPDATE ON definitions
    FOR EACH ROW EXECUTE PROCEDURE history_definitions();


-- It stores a general list of OUI (Organizationally Unique Identifier) to allow lookup of MAC address to 
-- owning company. Data for this comes from http://standards-oui.ieee.org/oui/oui.txt and is stored by 
-- striker-parse-oui. It is a generic reference table, so it's not bound to any one host.
CREATE TABLE oui (
    oui_uuid               uuid                        not null    primary key,
    oui_mac_prefix         text                        not null,                   -- This is the first 12 bits / 3 bytes of the MAC address
    oui_company_name       text                        not null,                   -- This is the name of the owning company, as recorded in the OUI list.
    oui_company_address    text                        not null,                   -- This is the company's registered address.
    modified_date          timestamp with time zone    not null 
);
ALTER TABLE oui OWNER TO admin;

CREATE TABLE history.oui (
    history_id             bigserial, 
    oui_uuid               uuid, 
    oui_mac_prefix         text, 
    oui_company_name       text, 
    oui_company_address    text, 
    modified_date          timestamp with time zone    not null
);
ALTER TABLE history.oui OWNER TO admin;

CREATE FUNCTION history_oui() RETURNS trigger
AS $$
DECLARE
    history_oui RECORD;
BEGIN
    SELECT INTO history_oui * FROM oui WHERE oui_uuid = new.oui_uuid;
    INSERT INTO history.oui
        (oui_uuid, 
         oui_mac_prefix, 
         oui_company_name, 
         oui_company_address, 
         modified_date)
    VALUES
        (history_oui.oui_uuid, 
         history_oui.oui_mac_prefix, 
         history_oui.oui_company_name, 
         history_oui.oui_company_address, 
         history_oui.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_oui() OWNER TO admin;

CREATE TRIGGER trigger_oui
    AFTER INSERT OR UPDATE ON oui
    FOR EACH ROW EXECUTE PROCEDURE history_oui();


-- It stores a general list of MAC addresses to IP addresses. This may belong to equipment outside the 
-- Anvil!, so there's no reference to other tables or a host_uuid.
CREATE TABLE mac_to_ip (
    mac_to_ip_uuid           uuid                        not null    primary key,
    mac_to_ip_mac_address    text                        not null, 
    mac_to_ip_ip_address     text                        not null, 
    mac_to_ip_note           text                        not null,                   -- This is a free-form note, and may contain a server name or host name, if we know it.
    modified_date            timestamp with time zone    not null 
);
ALTER TABLE mac_to_ip OWNER TO admin;

CREATE TABLE history.mac_to_ip (
    history_id               bigserial, 
    mac_to_ip_uuid           uuid, 
    mac_to_ip_mac_address    text, 
    mac_to_ip_ip_address     text, 
    mac_to_ip_note           text, 
    modified_date            timestamp with time zone    not null
);
ALTER TABLE history.mac_to_ip OWNER TO admin;

CREATE FUNCTION history_mac_to_ip() RETURNS trigger
AS $$
DECLARE
    history_mac_to_ip RECORD;
BEGIN
    SELECT INTO history_mac_to_ip * FROM mac_to_ip WHERE mac_to_ip_uuid = new.mac_to_ip_uuid;
    INSERT INTO history.mac_to_ip
        (mac_to_ip_uuid, 
         mac_to_ip_mac_address, 
         mac_to_ip_ip_address, 
         mac_to_ip_note, 
         modified_date)
    VALUES
        (history_mac_to_ip.mac_to_ip_uuid, 
         history_mac_to_ip.mac_to_ip_mac_address, 
         history_mac_to_ip.mac_to_ip_ip_address, 
         history_mac_to_ip.mac_to_ip_note, 
         history_mac_to_ip.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_mac_to_ip() OWNER TO admin;

CREATE TRIGGER trigger_mac_to_ip
    AFTER INSERT OR UPDATE ON mac_to_ip
    FOR EACH ROW EXECUTE PROCEDURE history_mac_to_ip();


-- This stores the information needed to build an Anvil! system.
CREATE TABLE manifests (
    manifest_uuid        uuid                        not null    primary key,
    manifest_name        text                        not null,                   -- The name of the manifest, defaults to being the Anvil!'s name
    manifest_last_ran    integer                     not null,                   -- This records the last time the manifest was run (in unix time). 
    manifest_xml         text                        not null,                   -- The XML body
    manifest_note        text                        not null,                   -- This is set to 'DELETED' when the manifest isn't needed anymore. Otherwise, it's a notepad for the user
    modified_date        timestamp with time zone    not null 
);
ALTER TABLE manifests OWNER TO admin;

CREATE TABLE history.manifests (
    history_id           bigserial, 
    manifest_uuid        uuid, 
    manifest_name        text,
    manifest_last_ran    integer,
    manifest_xml         text,
    manifest_note        text,
    modified_date        timestamp with time zone
);
ALTER TABLE history.manifests OWNER TO admin;

CREATE FUNCTION history_manifests() RETURNS trigger
AS $$
DECLARE
    history_manifests RECORD;
BEGIN
    SELECT INTO history_manifests * FROM manifests WHERE manifest_uuid = new.manifest_uuid;
    INSERT INTO history.manifests
        (manifest_uuid, 
         manifest_name,
         manifest_last_ran,
         manifest_xml,
         manifest_note,
         modified_date)
    VALUES
        (history_manifests.manifest_uuid, 
         history_manifests.manifest_name,
         history_manifests.manifest_last_ran,
         history_manifests.manifest_xml,
         history_manifests.manifest_note,
         history_manifests.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_manifests() OWNER TO admin;

CREATE TRIGGER trigger_manifests
    AFTER INSERT OR UPDATE ON manifests
    FOR EACH ROW EXECUTE PROCEDURE history_manifests();


-- This stores the information about fence devices (PDUs, KVM hosts, etc, minus IPMI which is stored in 'hosts')
CREATE TABLE fences (
    fence_uuid         uuid                        not null    primary key,
    fence_name         text                        not null,                   -- This is the name of the fence device. Usually this is the host name of the device (ie: xx-pdu01.example.com)
    fence_agent        text                        not null,                   -- This is the fence agent name used to communicate with the device. ie: 'fence_apc_ups', 'fence_virsh', etc.
    fence_arguments    text                        not null,                   -- This is the arguemnts list used to access / authenticate with the device. What should be in this field depends on the 'STDIN PARAMETERS' section of the fence agent's man page. 
    modified_date      timestamp with time zone    not null 
);
ALTER TABLE fences OWNER TO admin;

CREATE TABLE history.fences (
    history_id         bigserial, 
    fence_uuid         uuid, 
    fence_name         text,
    fence_agent        text, 
    fence_arguments    text, 
    modified_date      timestamp with time zone
);
ALTER TABLE history.fences OWNER TO admin;

CREATE FUNCTION history_fences() RETURNS trigger
AS $$
DECLARE
    history_fences RECORD;
BEGIN
    SELECT INTO history_fences * FROM fences WHERE fence_uuid = new.fence_uuid;
    INSERT INTO history.fences
        (fence_uuid, 
         fence_name,
         fence_agent, 
         fence_arguments, 
         modified_date)
    VALUES
        (history_fences.fence_uuid, 
         history_fences.fence_name,
         history_fences.fence_agent, 
         history_fences.fence_arguments, 
         history_fences.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_fences() OWNER TO admin;

CREATE TRIGGER trigger_fences
    AFTER INSERT OR UPDATE ON fences
    FOR EACH ROW EXECUTE PROCEDURE history_fences();


-- This stores the information about UPSes powering devices.
CREATE TABLE upses (
    ups_uuid          uuid                        not null    primary key,
    ups_name          text                        not null,                   -- This is the name of the ups device. Usually this is the host name of the device (ie: xx-pdu01.example.com)
    ups_agent         text                        not null,                   -- This is the ups agent name used to communicate with the device. ie: 'ups_apc_ups', 'ups_virsh', etc.
    ups_ip_address    text                        not null,                   -- This is the IP address of the UPS
    modified_date     timestamp with time zone    not null 
);
ALTER TABLE upses OWNER TO admin;

CREATE TABLE history.upses (
    history_id        bigserial, 
    ups_uuid          uuid, 
    ups_name          text,
    ups_agent         text, 
    ups_ip_address    text, 
    modified_date     timestamp with time zone
);
ALTER TABLE history.upses OWNER TO admin;

CREATE FUNCTION history_upses() RETURNS trigger
AS $$
DECLARE
    history_upses RECORD;
BEGIN
    SELECT INTO history_upses * FROM upses WHERE ups_uuid = new.ups_uuid;
    INSERT INTO history.upses
        (ups_uuid, 
         ups_name,
         ups_agent, 
         ups_ip_address, 
         modified_date)
    VALUES
        (history_upses.ups_uuid, 
         history_upses.ups_name,
         history_upses.ups_agent, 
         history_upses.ups_ip_address, 
         history_upses.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_upses() OWNER TO admin;

CREATE TRIGGER trigger_upses
    AFTER INSERT OR UPDATE ON upses
    FOR EACH ROW EXECUTE PROCEDURE history_upses();


-- ------------------------------------------------------------------------------------------------------- --
-- These are special tables with no history or tracking UUIDs that simply record transient information.    --
-- ------------------------------------------------------------------------------------------------------- --


-- This table records the last time a scan ran. It's sole purpose is to make sure at least one table's
-- 'modified_date' changes per run, so that database resyncs can be triggered reliably.
CREATE TABLE updated (
    updated_host_uuid    uuid                        not null,
    updated_by           text                        not null,    -- The name of the agent (or "ScanCore' itself) that updated.
    modified_date        timestamp with time zone    not null,
    
    FOREIGN KEY(updated_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE updated OWNER TO admin;


-- To avoid "waffling" when a sensor is close to an alert (or cleared) threshold, a gap between the alarm 
-- value and the clear value is used. If the sensor climbs above (or below) the "clear" value, but didn't 
-- previously pass the "alert" threshold, we DON'T want to send an "all clear" message. So do solve that, 
-- this table is used by agents to record when a warning message was sent. 
CREATE TABLE alert_sent (
    alert_sent_uuid         uuid                        not null    primary key,
    alert_sent_host_uuid    uuid                        not null,                   -- The node associated with this alert
    alert_set_by            text                        not null,                   -- name of the program that set this alert
    alert_record_locator    text                        not null,                   -- String used by the agent to identify the source of the alert (ie: UPS serial number)
    alert_name              text                        not null,                   -- A free-form name used by the caller to identify this alert.
    modified_date           timestamp with time zone    not null,
    
    FOREIGN KEY(alert_sent_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE updated OWNER TO admin;


-- NOTE: We don't resync this table! It's meant to be a transient data store, sometimes on a per-DB basis
-- This stores state information, like the whether migrations are happening and so on.
CREATE TABLE states (
    state_uuid         uuid                        not null    primary key,
    state_name         text                        not null,                   -- This is the name of the state (ie: 'migration', etc)
    state_host_uuid    uuid                        not null,                   -- The UUID of the machine that the state relates to. In migrations, this is the UUID of the target
    state_note         text                        not null,                   -- This is a free-form note section that the application setting the state can use for extra information (like the name of the server being migrated)
    modified_date      timestamp with time zone    not null,
    
    FOREIGN KEY(state_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE states OWNER TO admin;
