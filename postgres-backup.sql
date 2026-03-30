--
-- PostgreSQL database cluster dump
--

\restrict PgVLXlCG8a1SzAbDGsHJYjatQxQXuVHWyanWzUYrwqKnMlmTld9OHeszoDGRI0w

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE atoloanuser;
ALTER ROLE atoloanuser WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:uN/V26LTGgfvoeDurCeTMQ==$U4nhfYGc2si9VVzT0o7MEt2kWHGd9jp8W6e9Cuafu0s=:sUEJV8wt39qi2ENc2Dq2ko5Go295bAOIv8e4f0cf74Q=';

--
-- User Configurations
--








\unrestrict PgVLXlCG8a1SzAbDGsHJYjatQxQXuVHWyanWzUYrwqKnMlmTld9OHeszoDGRI0w

--
-- Databases
--

--
-- Database "template1" dump
--

\connect template1

--
-- PostgreSQL database dump
--

\restrict Voh7xZsgqnJZCJ3lnVIodPG833FG0otK4PCJzlQ6PNU4U4630sWySUdjnI9Lmgg

-- Dumped from database version 15.17 (Debian 15.17-1.pgdg13+1)
-- Dumped by pg_dump version 15.17 (Debian 15.17-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- PostgreSQL database dump complete
--

\unrestrict Voh7xZsgqnJZCJ3lnVIodPG833FG0otK4PCJzlQ6PNU4U4630sWySUdjnI9Lmgg

--
-- Database "atoloandb" dump
--

--
-- PostgreSQL database dump
--

\restrict d0XOWF0GGONwEMj1VFsZAo3bsntRqsINYdh3yTdKLeBuDGk1BXdvIpzTOxrUqIU

-- Dumped from database version 15.17 (Debian 15.17-1.pgdg13+1)
-- Dumped by pg_dump version 15.17 (Debian 15.17-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: atoloandb; Type: DATABASE; Schema: -; Owner: atoloanuser
--

CREATE DATABASE atoloandb WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'en_US.utf8';


ALTER DATABASE atoloandb OWNER TO atoloanuser;

\unrestrict d0XOWF0GGONwEMj1VFsZAo3bsntRqsINYdh3yTdKLeBuDGk1BXdvIpzTOxrUqIU
\connect atoloandb
\restrict d0XOWF0GGONwEMj1VFsZAo3bsntRqsINYdh3yTdKLeBuDGk1BXdvIpzTOxrUqIU

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- PostgreSQL database dump complete
--

\unrestrict d0XOWF0GGONwEMj1VFsZAo3bsntRqsINYdh3yTdKLeBuDGk1BXdvIpzTOxrUqIU

--
-- Database "postgres" dump
--

\connect postgres

--
-- PostgreSQL database dump
--

\restrict 0fJyXpaJmGPGlI92GsdoJ3VxNA6et3AVEatd8GEz8Veq4YEOhaeIWew9c7c42Z5

-- Dumped from database version 15.17 (Debian 15.17-1.pgdg13+1)
-- Dumped by pg_dump version 15.17 (Debian 15.17-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- PostgreSQL database dump complete
--

\unrestrict 0fJyXpaJmGPGlI92GsdoJ3VxNA6et3AVEatd8GEz8Veq4YEOhaeIWew9c7c42Z5

--
-- PostgreSQL database cluster dump complete
--

