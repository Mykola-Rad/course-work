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

CREATE TYPE public.invoice_type AS ENUM (
    'supply',        
    'transfer',      
    'release'
);

ALTER TYPE public.invoice_type OWNER TO postgres;

CREATE TYPE public.user_role AS ENUM (
    'owner',
    'manager',
    'storage_keeper'
);

ALTER TYPE public.user_role OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

CREATE TABLE public.counterparty (
    phone_number character varying(13) NOT NULL,
    name character varying(100) NOT NULL,
    email character varying(255),
    CONSTRAINT check_counterparty_phone_number CHECK (((phone_number)::text ~ '^\+[0-9]+$'::text))
);


ALTER TABLE public.counterparty OWNER TO postgres;

CREATE TABLE public.invoice (
    invoice_id integer NOT NULL,
    counterparty_name character varying(100),
    sender_keeper_phone character varying(13),
    receiver_keeper_phone character varying(13),
    sender_storage_name character varying(100),
    receiver_storage_name character varying(100),
    date date DEFAULT CURRENT_DATE NOT NULL,
    total_price numeric(20,2) NOT NULL,
    type public.invoice_type NOT NULL,
    CONSTRAINT check_invoice_date CHECK ((date <= CURRENT_DATE)),
    CONSTRAINT invoice_total_price_check CHECK ((total_price > (0)::numeric)),
    CONSTRAINT invoice_type_fields_check CHECK (
    (
        type = 'supply' AND
        sender_storage_name IS NULL AND
        receiver_storage_name IS NOT NULL AND
        sender_keeper_phone IS NULL AND
        receiver_keeper_phone IS NULL AND
        counterparty_name IS NOT NULL
    ) OR (
        type = 'transfer' AND
        sender_storage_name IS NOT NULL AND
        receiver_storage_name IS NOT NULL AND
        sender_keeper_phone IS NOT NULL AND
        receiver_keeper_phone IS NOT NULL AND
        counterparty_name IS NULL AND
        sender_storage_name <> receiver_storage_name AND
        sender_keeper_phone <> receiver_keeper_phone
    ) OR (
        type = 'release' AND
        sender_storage_name IS NOT NULL AND
        receiver_storage_name IS NULL AND
        sender_keeper_phone IS NULL AND
        receiver_keeper_phone IS NULL AND
        counterparty_name IS NOT NULL
    ))
);


ALTER TABLE public.invoice OWNER TO postgres;

CREATE SEQUENCE public.invoice_invoice_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.invoice_invoice_id_seq OWNER TO postgres;

ALTER SEQUENCE public.invoice_invoice_id_seq OWNED BY public.invoice.invoice_id;

CREATE TABLE public.list_entry (
    invoice_id integer NOT NULL,
    product_name character varying(100) NOT NULL,
    count numeric(10,2) NOT NULL,
    price numeric(10,2) NOT NULL,
    CONSTRAINT list_entry_count_check CHECK (((count)::double precision > (0)::double precision)),
    CONSTRAINT list_entry_price_check CHECK ((price > (0)::numeric))
);

ALTER TABLE public.list_entry OWNER TO postgres;

CREATE TABLE public.product_units (
    unit_code character varying(10) NOT NULL, 
    unit_name character varying(50) NOT NULL, 
    CONSTRAINT product_units_pkey PRIMARY KEY (unit_code),
    CONSTRAINT unique_product_unit_name UNIQUE (unit_name)
);

ALTER TABLE public.product_units OWNER TO postgres;

CREATE TABLE public.product (
    product_name character varying(100) NOT NULL,
    unit_code character varying(10) NOT NULL,
    last_price numeric(10,2) NOT NULL,
    CONSTRAINT product_current_price_check CHECK ((last_price > (0)::numeric))
);

ALTER TABLE public.product OWNER TO postgres;

CREATE TABLE public.storage (
    name character varying(100) NOT NULL,
    street_name character varying(100) NOT NULL,
    house_number character varying(3) NOT NULL,
    city character varying(50) NOT NULL,
    region character varying(30) NOT NULL,
    postal_code character varying(8) NOT NULL,
    CONSTRAINT check_postal_code CHECK (((postal_code)::text ~ '^[0-9]+$'::text))
);

ALTER TABLE public.storage OWNER TO postgres;

CREATE TABLE public.user (
    username varchar(101) NOT NULL,
    password_hash varchar(255) NOT NULL,
    role public.user_role NOT NULL
);

ALTER TABLE public.user OWNER TO postgres;

CREATE TABLE public.storage_keeper (
    phone_number character varying(13) NOT NULL,
    storage_name character varying(100) NOT NULL,
    username varchar(50) UNIQUE,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    email character varying(255)
);

ALTER TABLE public.storage_keeper OWNER TO postgres;

CREATE TABLE public.storage_product (
    storage_name character varying(100) NOT NULL,
    product_name character varying(100) NOT NULL,
    count numeric(10,2) NOT NULL,
    CONSTRAINT storage_product_count_check CHECK (((count)::double precision > (0)::double precision))
);

ALTER TABLE public.storage_product OWNER TO postgres;

ALTER TABLE ONLY public.invoice ALTER COLUMN invoice_id SET DEFAULT nextval('public.invoice_invoice_id_seq'::regclass);

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_pkey PRIMARY KEY (invoice_id);

ALTER TABLE ONLY public.list_entry
    ADD CONSTRAINT list_entry_pkey PRIMARY KEY (product_name, invoice_id);

ALTER TABLE ONLY public.product
    ADD CONSTRAINT product_pkey PRIMARY KEY (product_name);

ALTER TABLE ONLY public.storage
    ADD CONSTRAINT storage_pkey PRIMARY KEY (name);

ALTER TABLE ONLY public.counterparty
    ADD CONSTRAINT provider_pkey PRIMARY KEY (name);

ALTER TABLE ONLY public.storage_keeper
    ADD CONSTRAINT storage_keeper_pkey PRIMARY KEY (phone_number);

ALTER TABLE ONLY public.storage_product
    ADD CONSTRAINT storage_product_pkey PRIMARY KEY (product_name, storage_name);

ALTER TABLE ONLY public.user
    ADD CONSTRAINT user_pkey PRIMARY KEY (username);

ALTER TABLE ONLY public.product
    ADD CONSTRAINT unique_product_name UNIQUE (product_name);

ALTER TABLE ONLY public.counterparty
    ADD CONSTRAINT unique_counterparty_email UNIQUE (email);

ALTER TABLE ONLY public.counterparty
    ADD CONSTRAINT unique_counterparty_phone_number UNIQUE (phone_number);

ALTER TABLE ONLY public.storage_keeper
    ADD CONSTRAINT unique_storage_keeper_email UNIQUE (email);

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_counterparty_name_fkey FOREIGN KEY (counterparty_name) REFERENCES public.counterparty(name) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE ONLY public.storage_keeper
    ADD CONSTRAINT storage_keeper_username_fkey FOREIGN KEY (username) REFERENCES public.user(username) ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_sender_storage_name_fkey FOREIGN KEY (sender_storage_name) REFERENCES public.storage(name) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_sender_keeper_phone_fkey FOREIGN KEY (sender_keeper_phone) REFERENCES public.storage_keeper(phone_number) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_receiver_storage_name_fkey FOREIGN KEY (receiver_storage_name) REFERENCES public.storage(name) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_receiver_keeper_phone_fkey FOREIGN KEY (receiver_keeper_phone) REFERENCES public.storage_keeper(phone_number) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE ONLY public.list_entry
    ADD CONSTRAINT list_entry_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoice(invoice_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.list_entry
    ADD CONSTRAINT list_entry_product_name_fkey FOREIGN KEY (product_name) REFERENCES public.product(product_name) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE ONLY public.storage_keeper
    ADD CONSTRAINT storage_keeper_storage_name_fkey FOREIGN KEY (storage_name) REFERENCES public.storage(name) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE ONLY public.storage_product
    ADD CONSTRAINT storage_product_product_name_fkey FOREIGN KEY (product_name) REFERENCES public.product(product_name) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE ONLY public.storage_product
    ADD CONSTRAINT storage_product_storage_name_fkey FOREIGN KEY (storage_name) REFERENCES public.storage(name) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE ONLY public.product
    ADD CONSTRAINT product_unit_code_fkey FOREIGN KEY (unit_code) REFERENCES public.product_units(unit_code) ON UPDATE CASCADE ON DELETE RESTRICT;


    ALTER TABLE public.storage_product
ADD COLUMN minimal_count numeric(10,2) DEFAULT 0 NOT NULL,
ADD CONSTRAINT storage_product_minimal_count_check CHECK (minimal_count >= 0);
