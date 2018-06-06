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

-- This stores information about users. 
-- Note that is all permissions are left false, the user can still interact with the Anvil! doing safe things, like changing optical media, perform migrations, start servers (but not stop them), etc. 
CREATE TABLE users (
    user_uuid            uuid                        not null    primary key,    -- This is the single most important record in Anvil!. Everything links back to here.
    user_name            text                        not null,
    user_password_hash   text                        not null,                   -- A user without a password is disabled.
    user_salt            text                        not null,                   -- This is used to enhance the security of the user's password.
    user_algorithm       text                        not null,                   -- This is the algorithm used to encrypt the password and salt.
    user_hash_count      text                        not null,                   -- This is the number of times that the password+salt was re-hashed through the algorithm.
    user_language        text                        not null,                   -- If set, this will choose a different language over the default.
    user_is_admin        integer                     not null    default 0,      -- If 1, all aspects of the program are available to the user. 
    user_is_experienced  integer                     not null    default 0,      -- If 1, user is allowed to delete a server, alter disk size, alter hardware and do other potentially risky things. They will also get fewer confirmation dialogues. 
    user_is_trusted      integer                     not null    default 0,      -- If 1, user is allowed to do things that would cause interruptions, like force-reset and gracefully stop servers, withdraw nodes, and stop the Anvil! entirely.
    modified_date        timestamp with time zone    not null
);
ALTER TABLE users OWNER TO #!variable!user!#;

CREATE TABLE history.users (
    history_id           bigserial,
    user_uuid            uuid,
    user_name            text,
    user_password_hash   text,
    user_salt            text,
    user_algorithm       text,
    user_hash_count      text,
    user_language        text,
    user_is_admin        integer,
    user_is_experienced  integer,
    user_is_trusted      integer,
    modified_date        timestamp with time zone    not null
);
ALTER TABLE history.users OWNER TO #!variable!user!#;

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
ALTER FUNCTION history_users() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_users
    AFTER INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE PROCEDURE history_users();



-- This stores information about the host machine. This is the master table that everything will be linked 
-- to. 
CREATE TABLE hosts (
    host_uuid        uuid                        not null    primary key,    -- This is the single most important record in Anvil!. Everything links back to here.
    host_name        text                        not null,
    host_type        text                        not null,            -- Either 'node' or 'dashboard'.
    modified_date    timestamp with time zone    not null
);
ALTER TABLE hosts OWNER TO #!variable!user!#;

CREATE TABLE history.hosts (
    history_id       bigserial,
    host_uuid        uuid                        not null,
    host_name        text                        not null,
    host_type        text                        not null,
    modified_date    timestamp with time zone    not null
);
ALTER TABLE history.hosts OWNER TO #!variable!user!#;

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
         modified_date)
    VALUES
        (history_hosts.host_uuid,
         history_hosts.host_name,
         history_hosts.host_type,
         history_hosts.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_hosts() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_hosts
    AFTER INSERT OR UPDATE ON hosts
    FOR EACH ROW EXECUTE PROCEDURE history_hosts();


-- This stores special variables for a given host that programs may want to record.
CREATE TABLE host_variable (
    host_variable_uuid         uuid                        not null    primary key,    -- This is the single most important record in ScanCore. Everything links back to here.
    host_variable_host_uuid    uuid                        not null,
    host_variable_name         text                        not null,
    host_variable_value        text                        not null,
    modified_date              timestamp with time zone    not null
);
ALTER TABLE host_variable OWNER TO #!variable!user!#;

CREATE TABLE history.host_variable (
    history_id                 bigserial,
    host_variable_uuid         uuid,
    host_variable_host_uuid    uuid,
    host_variable_name         text,
    host_variable_value        text,
    modified_date              timestamp with time zone    not null
);
ALTER TABLE history.host_variable OWNER TO #!variable!user!#;

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
ALTER FUNCTION history_host_variable() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_host_variable
    AFTER INSERT OR UPDATE ON host_variable
    FOR EACH ROW EXECUTE PROCEDURE history_host_variable();


-- This stores alerts coming in from various sources
CREATE TABLE alerts (
    alert_uuid                 uuid                        not null    primary key,
    alert_host_uuid            uuid                        not null,                    -- The name of the node or dashboard that this alert came from.
    alert_set_by               text                        not null,
    alert_level                text                        not null,                    -- debug (log only), info (+ admin email), notice (+ curious users), warning (+ client technical staff), critical (+ all)
    alert_title_key            text                        not null,                    -- ScanCore will read in the agents <name>.xml words file and look for this message key
    alert_title_variables      text                        not null,                    -- List of variables to substitute into the message key. Format is 'var1=val1 #!# var2 #!# val2 #!# ... #!# varN=valN'.
    alert_message_key          text                        not null,                    -- ScanCore will read in the agents <name>.xml words file and look for this message key
    alert_message_variables    text                        not null,                    -- List of variables to substitute into the message key. Format is 'var1=val1 #!# var2 #!# val2 #!# ... #!# varN=valN'.
    alert_sort                 text                        not null,                    -- The alerts will sort on this column. It allows for an optional sorting of the messages in the alert.
    alert_header               integer                     not null    default 1,       -- This can be set to have the alert be printed with only the contents of the string, no headers.
    modified_date              timestamp with time zone    not null,
    
    FOREIGN KEY(alert_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE alerts OWNER TO #!variable!user!#;

CREATE TABLE history.alerts (
    history_id                 bigserial,
    alert_uuid                 uuid,
    alert_host_uuid            uuid,
    alert_set_by               text,
    alert_level                text,
    alert_title_key            text,
    alert_title_variables      text,
    alert_message_key          text,
    alert_message_variables    text,
    alert_sort                 text,
    alert_header               integer,
    modified_date              timestamp with time zone    not null
);
ALTER TABLE history.alerts OWNER TO #!variable!user!#;

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
         alert_title_key,
         alert_title_variables,
         alert_message_key,
         alert_message_variables,
         alert_sort, 
         alert_header, 
         modified_date)
    VALUES
        (history_alerts.alert_uuid,
         history_alerts.alert_host_uuid,
         history_alerts.alert_set_by,
         history_alerts.alert_level,
         history_alerts.alert_title_key,
         history_alerts.alert_title_variables,
         history_alerts.alert_message_key,
         history_alerts.alert_message_variables,
         history_alerts.alert_sort, 
         history_alerts.alert_header, 
         history_alerts.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_alerts() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_alerts
    AFTER INSERT OR UPDATE ON alerts
    FOR EACH ROW EXECUTE PROCEDURE history_alerts();


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
ALTER TABLE variables OWNER TO #!variable!user!#;

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
ALTER TABLE history.variables OWNER TO #!variable!user!#;

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
ALTER FUNCTION history_variables() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_variables
    AFTER INSERT OR UPDATE ON variables
    FOR EACH ROW EXECUTE PROCEDURE history_variables();


-- This holds jobs to be run.
CREATE TABLE jobs (
    job_uuid           uuid                        not null    primary key,    -- 
    job_host_uuid      uuid                        not null,                   -- This is the host that requested the job
    job_command        text                        not null,                   -- This is the command to run (usually a shell call).
    job_data           text                        not null,                   -- This is optional data to be used by anvil-data 
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
ALTER TABLE jobs OWNER TO #!variable!user!#;

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
ALTER TABLE history.jobs OWNER TO #!variable!user!#;

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
ALTER FUNCTION history_jobs() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_jobs
    AFTER INSERT OR UPDATE ON jobs
    FOR EACH ROW EXECUTE PROCEDURE history_jobs();

-- NOTE: network_interfaces, network_bonds and network_bridges are all used by scan-network (which doesn't 
--       exist yet).

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
    modified_date                    timestamp with time zone    not null
);
ALTER TABLE network_interfaces OWNER TO #!variable!user!#;

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
ALTER TABLE history.network_interfaces OWNER TO #!variable!user!#;

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
ALTER FUNCTION history_network_interfaces() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_network_interfaces
    AFTER INSERT OR UPDATE ON network_interfaces
    FOR EACH ROW EXECUTE PROCEDURE history_network_interfaces();


-- This stores information about network bonds (mode=1) on a hosts.
CREATE TABLE bonds (
    bond_uuid                    uuid                        not null    primary key,
    bond_host_uuid               uuid                        not null,
    bond_name                    text                        not null,
    bond_mode                    text                        not null,                   -- This is the numerical bond type (will translate to the user's language in the Anvil!)
    bond_mtu                     bigint                      not null,
    bond_primary_slave           text                        not null,
    bond_primary_reselect        text                        not null,
    bond_active_slave            text                        not null,
    bond_mii_polling_interval    bigint                      not null,
    bond_up_delay                bigint                      not null,
    bond_down_delay              bigint                      not null,
    bond_mac_address             text                        not null,
    bond_operational             text                        not null,                   -- This is 'up', 'down' or 'unknown' 
    modified_date                timestamp with time zone    not null,
    
    FOREIGN KEY(bond_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE bonds OWNER TO #!variable!user!#;

CREATE TABLE history.bonds (
    history_id                   bigserial,
    bond_uuid                    uuid,
    bond_host_uuid               uuid,
    bond_name                    text,
    bond_mode                    text,
    bond_mtu                     bigint,
    bond_primary_slave           text,
    bond_primary_reselect        text,
    bond_active_slave            text,
    bond_mii_polling_interval    bigint,
    bond_up_delay                bigint,
    bond_down_delay              bigint,
    bond_mac_address             text, 
    bond_operational             text,
    modified_date                timestamp with time zone    not null
);
ALTER TABLE history.bonds OWNER TO #!variable!user!#;

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
         bond_primary_slave, 
         bond_primary_reselect, 
         bond_active_slave, 
         bond_mii_polling_interval, 
         bond_up_delay, 
         bond_down_delay, 
         bond_mac_address, 
         bond_operational, 
         modified_date)
    VALUES
        (history_bonds.bond_uuid,
         history_bonds.bond_host_uuid,
         history_bonds.bond_name, 
         history_bonds.bond_mode, 
         history_bonds.bond_mtu, 
         history_bonds.bond_primary_slave, 
         history_bonds.bond_primary_reselect, 
         history_bonds.bond_active_slave, 
         history_bonds.bond_mii_polling_interval, 
         history_bonds.bond_up_delay, 
         history_bonds.bond_down_delay, 
         history_bonds.bond_mac_address, 
         history_bonds.bond_operational, 
         history_bonds.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_bonds() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_bonds
    AFTER INSERT OR UPDATE ON bonds
    FOR EACH ROW EXECUTE PROCEDURE history_bonds();


-- This stores information about network bridges. 
CREATE TABLE bridges (
    bridge_uuid           uuid                        not null    primary key,
    bridge_host_uuid      uuid                        not null,
    bridge_name           text                        not null,
    bridge_id             text                        not null,
    bridge_stp_enabled    text                        not null,
    modified_date         timestamp with time zone    not null,
    
    FOREIGN KEY(bridge_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE bridges OWNER TO #!variable!user!#;

CREATE TABLE history.bridges (
    history_id            bigserial,
    bridge_uuid           uuid,
    bridge_host_uuid      uuid,
    bridge_name           text,
    bridge_id             text,
    bridge_stp_enabled    text,
    modified_date         timestamp with time zone    not null
);
ALTER TABLE history.bridges OWNER TO #!variable!user!#;

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
         bridge_name,
         bridge_id,
         bridge_stp_enabled,
         modified_date)
    VALUES
        (history_bridges.bridge_uuid, 
         history_bridges.bridge_host_uuid, 
         history_bridges.bridge_name, 
         history_bridges.bridge_name, 
         history_bridges.bridge_id, 
         history_bridges.bridge_stp_enabled, 
         history_bridges.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_bridges() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_bridges
    AFTER INSERT OR UPDATE ON bridges
    FOR EACH ROW EXECUTE PROCEDURE history_bridges();


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
    modified_date                 timestamp with time zone    not null,
    
    FOREIGN KEY(ip_address_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE ip_addresses OWNER TO #!variable!user!#;

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
    modified_date                 timestamp with time zone    not null
);
ALTER TABLE history.ip_addresses OWNER TO #!variable!user!#;

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
         history_ip_addresses.ip_address_dns, 
         history_ip_addresses.modified_date);
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_ip_addresses() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_ip_addresses
    AFTER INSERT OR UPDATE ON ip_addresses
    FOR EACH ROW EXECUTE PROCEDURE history_ip_addresses();


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
ALTER TABLE updated OWNER TO #!variable!user!#;


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
ALTER TABLE updated OWNER TO #!variable!user!#;


-- This stores state information, like the whether migrations are happening and so on.
CREATE TABLE states (
    state_uuid         uuid                        not null    primary key,
    state_name         text                        not null,                   -- This is the name of the state (ie: 'migration', etc)
    state_host_uuid    uuid                        not null,                   -- The UUID of the machine that the state relates to. In migrations, this is the UUID of the target
    state_note         text                        not null,                   -- This is a free-form note section that the application setting the state can use for extra information (like the name of the server being migrated)
    modified_date      timestamp with time zone    not null,
    
    FOREIGN KEY(state_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE states OWNER TO #!variable!user!#;
