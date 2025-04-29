--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4
-- Dumped by pg_dump version 16.4

-- Started on 2025-04-26 13:34:40

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
-- TOC entry 885 (class 1247 OID 24653)
-- Name: counterparty_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.counterparty_type AS ENUM (
    'provider',
    'customer'
);


ALTER TYPE public.counterparty_type OWNER TO postgres;

--
-- TOC entry 882 (class 1247 OID 24647)
-- Name: invoice_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.invoice_type AS ENUM (
    'in',
    'out'
);


ALTER TYPE public.invoice_type OWNER TO postgres;

--
-- TOC entry 239 (class 1255 OID 33038)
-- Name: calculate_discounted_price(numeric, double precision, double precision); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_discounted_price(price numeric, quantity double precision, discount double precision DEFAULT 0.1) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN ROUND((price * quantity) * (1 - discount), 2);
END;
$$;


ALTER FUNCTION public.calculate_discounted_price(price numeric, quantity double precision, discount double precision) OWNER TO postgres;

--
-- TOC entry 243 (class 1255 OID 33045)
-- Name: check_product_integrity(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_product_integrity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NOT EXISTS (SELECT 1 FROM product WHERE product_name = NEW.product_name) THEN
            RAISE EXCEPTION 'Product "%" does not exist in the product table', NEW.product_name;
        END IF;

        IF NEW.count <= 0 THEN
            RAISE EXCEPTION 'Count for product "%" must be greater than 0', NEW.product_name;
        END IF;

		 RETURN NEW;
    END IF;
    
    IF TG_OP = 'UPDATE' THEN
        IF NOT EXISTS (SELECT 1 FROM product WHERE product_name = NEW.product_name) THEN
            RAISE EXCEPTION 'Product "%" does not exist in the product table', NEW.product_name;
        END IF;

        IF NEW.count <= 0 THEN
            RAISE EXCEPTION 'Count for product "%" must be greater than 0', NEW.product_name;
        END IF;

		 RETURN NEW;
    END IF;
    
    IF TG_OP = 'DELETE' THEN
         IF NOT EXISTS (SELECT 1 FROM product WHERE product_name = OLD.product_name) THEN
            RAISE EXCEPTION 'Product "%" does not exist in the product table', OLD.product_name;
        END IF;

		 RETURN OLD;
    END IF;
    
   
END;
$$;


ALTER FUNCTION public.check_product_integrity() OWNER TO postgres;

--
-- TOC entry 245 (class 1255 OID 33051)
-- Name: check_storage_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_storage_stock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (SELECT type 
        FROM public.invoice 
        WHERE invoice_id = NEW.invoice_id) = 'out' THEN

        IF NOT EXISTS (
            SELECT 1
            FROM public.storage_product
            WHERE storage_id = NEW.invoice_id
              AND product_name = NEW.product_name) THEN
            RAISE EXCEPTION 'Product "%" does not exist in the warehouse for invoice "%"', NEW.product_name, NEW.invoice_id;
        END IF;

        IF (SELECT count
            FROM public.storage_product
            WHERE storage_id = NEW.invoice_id
              AND product_name = NEW.product_name) < NEW.count THEN
            RAISE EXCEPTION 'Not enough stock of product "%" in the warehouse for invoice "%"', NEW.product_name, NEW.invoice_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_storage_stock() OWNER TO postgres;

--
-- TOC entry 241 (class 1255 OID 33033)
-- Name: create_invoice_snapshot(text, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.create_invoice_snapshot(IN target_table_name text, IN predicate text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('
        CREATE TABLE %I AS
        SELECT *
        FROM public.invoice
        WHERE %s', target_table_name, predicate);
 
    RAISE NOTICE 'Table "%" has been successfully created with invoices matching the condition: %', target_table_name, predicate;

EXCEPTION
    WHEN duplicate_table THEN
        RAISE WARNING 'The table "%" already exists. Please use a different name for the target table.', target_table_name;
    WHEN syntax_error THEN
        RAISE WARNING 'There is a syntax issue with the provided predicate: %', predicate;
    WHEN undefined_table THEN
        RAISE WARNING 'Table "invoice" does not exist. Ensure that the table is available in the database.';
    WHEN others THEN
        RAISE WARNING 'An unexpected error occurred while creating the table "%": %', target_table_name, SQLERRM;
END;
$$;


ALTER PROCEDURE public.create_invoice_snapshot(IN target_table_name text, IN predicate text) OWNER TO postgres;

--
-- TOC entry 247 (class 1255 OID 41283)
-- Name: export_all_storages(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.export_all_storages() RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
    all_storages_json JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
			'storage_name', 'Storage #' || s.storage_id,
            'street_name', s.street_name,
            'house_number', s.house_number,
            'city', s.city,
            'region', s.region,
            'postal_code', s.postal_code,
            'storage_keepers', (
                SELECT json_agg(
                    json_build_object(
                        'first_name', sk.first_name,
                        'last_name', sk.last_name, 
						'phone_number', sk.phone_number,
                        'email', sk.email
                    )
                )
                FROM public.storage_keeper sk
                WHERE sk.storage_id = s.storage_id
            ),
            'storage_products', (
                SELECT json_agg(
                    json_build_object(
                        'product', json_build_object(
                            'product_name', p.product_name,
                            'units', p.units,
                            'last_price', p.last_price
                        ),
                        'count', sp.count
                    )
                )
                FROM public.storage_product sp
                JOIN public.product p ON p.product_name = sp.product_name
                WHERE sp.storage_id = s.storage_id
            )
        )
    ) INTO all_storages_json
    FROM public.storage s;

    RETURN all_storages_json;
END;
$$;


ALTER FUNCTION public.export_all_storages() OWNER TO postgres;

--
-- TOC entry 244 (class 1255 OID 33042)
-- Name: get_low_stock_products(double precision); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_low_stock_products(min_quantity double precision) RETURNS TABLE(product_name character varying, total_count numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT sp.product_name, ROUND(SUM(sp.count)::numeric, 2) AS total_count
    FROM public.storage_product sp
    JOIN public.product p ON sp.product_name = p.product_name
    GROUP BY sp.product_name
    HAVING SUM(sp.count) < min_quantity
	ORDER BY total_count ASC, product_name;
END;
$$;


ALTER FUNCTION public.get_low_stock_products(min_quantity double precision) OWNER TO postgres;

--
-- TOC entry 240 (class 1255 OID 33006)
-- Name: get_supplier_invoice_summary(date, date); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.get_supplier_invoice_summary(IN start_date date, IN end_date date)
    LANGUAGE plpgsql
    AS $$
BEGIN
 IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'supplier_invoice_summary') THEN
        DROP TABLE supplier_invoice_summary;
    END IF;

    CREATE TEMPORARY TABLE supplier_invoice_summary AS
    SELECT
        i.counterparty_name AS supplier_name,
        COUNT(i.invoice_id) AS invoice_count,
        SUM(i.total_price) AS total_invoice_value
    FROM public.invoice i
    WHERE i.date BETWEEN start_date AND end_date AND i.type = 'in'
    GROUP BY i.counterparty_name;
	
    RAISE NOTICE 'Supplier Invoice Summary for period % to %', start_date, end_date;

EXCEPTION
    WHEN undefined_table THEN
        RAISE WARNING 'Table "invoice" or "counterparty" does not exist.';
		 WHEN duplicate_table THEN
        RAISE WARNING 'Temporary table "supplier_invoice_summary" already exists and was dropped.';
    WHEN others THEN
        RAISE WARNING 'An unexpected error occurred while creating table. %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.get_supplier_invoice_summary(IN start_date date, IN end_date date) OWNER TO postgres;

--
-- TOC entry 242 (class 1255 OID 33047)
-- Name: prevent_product_deletion(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.prevent_product_deletion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Перевірка існування записів у storage_product
    IF EXISTS (
        SELECT 1
        FROM storage_product
        WHERE product_name = OLD.product_name
    ) THEN
        RAISE EXCEPTION 'Cannot delete product "%", it is referenced in storage_product.', OLD.product_name;
    END IF;

    -- Перевірка існування записів у list_entry
    IF EXISTS (
        SELECT 1
        FROM list_entry
        WHERE product_name = OLD.product_name
    ) THEN
        RAISE EXCEPTION 'Cannot delete product "%", it is referenced in list_entry.', OLD.product_name;
    END IF;

    RETURN OLD;
END;
$$;


ALTER FUNCTION public.prevent_product_deletion() OWNER TO postgres;

--
-- TOC entry 246 (class 1255 OID 33055)
-- Name: update_last_price(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_last_price() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.product
    SET last_price = NEW.price
    WHERE product_name = NEW.product_name;
    RAISE NOTICE 'Updated last price of product "%" to %.', NEW.product_name, NEW.price;
	 
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_last_price() OWNER TO postgres;

--
-- TOC entry 238 (class 1255 OID 32997)
-- Name: update_product_count_from_invoice(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_product_count_from_invoice(IN _invoice_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    entry RECORD;
    invoice_type invoice_type;
    current_count DOUBLE PRECISION;
    _storage_id INT;
    product_cursor CURSOR FOR
        SELECT product_name, count
        FROM list_entry le
        WHERE le.invoice_id = _invoice_id;
BEGIN
    -- Отримуємо тип накладної і storage_id
    SELECT 
        type, 
        (SELECT storage_id FROM invoice i WHERE i.invoice_id = _invoice_id) 
    INTO invoice_type, _storage_id
    FROM invoice i
    WHERE i.invoice_id = _invoice_id;

    -- Відкриваємо курсор для обробки кожного продукту в накладній
    OPEN product_cursor;

    -- Обробляємо кожен продукт з курсора
    LOOP
        FETCH product_cursor INTO entry;
        EXIT WHEN NOT FOUND;

        IF invoice_type = 'in' THEN
            -- Для накладної на отримання збільшуємо кількість товару
            UPDATE storage_product
            SET count = count + entry.count
            WHERE product_name = entry.product_name
            AND storage_id = _storage_id;

            IF NOT FOUND THEN
                -- Якщо товар не знайдений, додаємо новий товар на склад
                INSERT INTO storage_product (product_name, count, storage_id)
                VALUES (entry.product_name, entry.count, _storage_id);
                RAISE NOTICE 'Added % of product % to storage', entry.count, entry.product_name;
            ELSE
                RAISE NOTICE 'Updated stock for product %: +% units', entry.product_name, entry.count;
            END IF;

        ELSIF invoice_type = 'out' THEN
            -- Для накладної на вилучення зменшуємо кількість товару
            SELECT count INTO current_count
            FROM storage_product
            WHERE product_name = entry.product_name
            AND storage_id = _storage_id;

            IF current_count IS NULL OR current_count < entry.count THEN
                -- Якщо товару на складі немає або його кількість менша за вказану в накладній
                RAISE EXCEPTION 'Not enough stock for product % on storage', entry.product_name;
            ELSE
                -- Якщо кількість товару на складі після вилучення не буде рівною 0, зменшуємо кількість
                IF current_count - entry.count > 0 THEN
                    UPDATE storage_product
                    SET count = count - entry.count
                    WHERE product_name = entry.product_name
                    AND storage_id = _storage_id;
                    RAISE NOTICE 'Reduced stock for product %: -% units', entry.product_name, entry.count;
                ELSE
                    -- Якщо кількість товару стане 0, видаляємо товар зі складу
                    DELETE FROM storage_product
                    WHERE product_name = entry.product_name
                    AND storage_id = _storage_id;
                    RAISE NOTICE 'Deleted product % from storage due to zero stock', entry.product_name;
                END IF;
            END IF;
        END IF;
    END LOOP;
    CLOSE product_cursor;
END;
$$;


ALTER PROCEDURE public.update_product_count_from_invoice(IN _invoice_id integer) OWNER TO postgres;

--
-- TOC entry 226 (class 1255 OID 41264)
-- Name: update_total_price(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_total_price() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE public.invoice
  SET total_price = (SELECT SUM(le.count * le.price)
                     FROM public.list_entry le
                     WHERE le.invoice_id = NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_total_price() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 217 (class 1259 OID 16508)
-- Name: counterparty; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counterparty (
    phone_number character varying(13) NOT NULL,
    name character varying(100) NOT NULL,
    email character varying(255),
    CONSTRAINT check_provider_phone_number CHECK (((phone_number)::text ~ '^\+[0-9]+$'::text))
);


ALTER TABLE public.counterparty OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 16539)
-- Name: invoice; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.invoice (
    invoice_id integer NOT NULL,
    counterparty_name character varying(100) NOT NULL,
    storage_keeper_phone character varying(13),
    storage_id integer NOT NULL,
    date date DEFAULT CURRENT_DATE NOT NULL,
    total_price numeric(20,2) NOT NULL,
    type public.invoice_type DEFAULT 'in'::public.invoice_type NOT NULL,
    CONSTRAINT check_invoice_date CHECK ((date <= CURRENT_DATE)),
    CONSTRAINT invoice_total_price_check CHECK ((total_price > (0)::numeric))
);


ALTER TABLE public.invoice OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 16538)
-- Name: invoice_invoice_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.invoice_invoice_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.invoice_invoice_id_seq OWNER TO postgres;

--
-- TOC entry 4956 (class 0 OID 0)
-- Dependencies: 222
-- Name: invoice_invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.invoice_invoice_id_seq OWNED BY public.invoice.invoice_id;


--
-- TOC entry 224 (class 1259 OID 16562)
-- Name: list_entry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.list_entry (
    invoice_id integer NOT NULL,
    product_name character varying(100) NOT NULL,
    count numeric(10,2) NOT NULL,
    price numeric(10,2) NOT NULL,
    CONSTRAINT list_entry_count_check CHECK (((count)::double precision > (0)::double precision)),
    CONSTRAINT list_entry_price_check CHECK ((price > (0)::numeric))
);


ALTER TABLE public.list_entry OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16532)
-- Name: product; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product (
    product_name character varying(100) NOT NULL,
    units character varying(5) NOT NULL,
    last_price numeric(10,2) NOT NULL,
    CONSTRAINT product_current_price_check CHECK ((last_price > (0)::numeric))
);


ALTER TABLE public.product OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 16514)
-- Name: storage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.storage (
    storage_id integer NOT NULL,
    street_name character varying(100) NOT NULL,
    house_number character varying(3) NOT NULL,
    city character varying(50) NOT NULL,
    region character varying(30) NOT NULL,
    postal_code character varying(8) NOT NULL,
    CONSTRAINT check_postal_code CHECK (((postal_code)::text ~ '^[0-9]+$'::text))
);


ALTER TABLE public.storage OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 16522)
-- Name: storage_keeper; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.storage_keeper (
    phone_number character varying(13) NOT NULL,
    storage_id integer NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    email character varying(255)
);


ALTER TABLE public.storage_keeper OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16581)
-- Name: storage_product; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.storage_product (
    storage_id integer NOT NULL,
    product_name character varying(100) NOT NULL,
    count numeric(10,2) NOT NULL,
    CONSTRAINT storage_product_count_check CHECK (((count)::double precision > (0)::double precision))
);


ALTER TABLE public.storage_product OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 16513)
-- Name: storage_storage_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.storage_storage_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.storage_storage_id_seq OWNER TO postgres;

--
-- TOC entry 4957 (class 0 OID 0)
-- Dependencies: 218
-- Name: storage_storage_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.storage_storage_id_seq OWNED BY public.storage.storage_id;


--
-- TOC entry 4733 (class 2604 OID 16542)
-- Name: invoice invoice_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoice ALTER COLUMN invoice_id SET DEFAULT nextval('public.invoice_invoice_id_seq'::regclass);


--
-- TOC entry 4732 (class 2604 OID 16517)
-- Name: storage storage_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage ALTER COLUMN storage_id SET DEFAULT nextval('public.storage_storage_id_seq'::regclass);


--
-- TOC entry 4942 (class 0 OID 16508)
-- Dependencies: 217
-- Data for Name: counterparty; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.counterparty (phone_number, name, email) FROM stdin;
+380949867947	Stiedemann, Beatty and Stiedemann	Giuseppe.Oberbrunner11@yahoo.com
+380657586278	Hills - Hintz	Madie55@gmail.com
+380017627169	Bartell Inc	Marquis_Howell@hotmail.com
+380574200606	Weimann - Beahan	Christophe23@yahoo.com
+380871483760	Kuhn - Schmeler	Rudy24@yahoo.com
+380138885827	Collier Inc	Kolby.Heidenreich20@yahoo.com
+380302342329	Torp, Rogahn and Schroeder	Kian81@yahoo.com
+380199449011	Labadie Inc	Hazle_Gulgowski@yahoo.com
+380660103525	Blick - Morar	Shane19@gmail.com
+380174646348	Ortiz - Oberbrunner	Raina.Hansen12@hotmail.com
+380989569958	Ledner, Bartoletti and Wuckert	Dorthy.Bartell41@hotmail.com
+380514905795	Schowalter - Schinner	Axel76@hotmail.com
+380623982590	Cremin, Walsh and Okuneva	Claudine_Parker98@hotmail.com
+380720270401	Ziemann LLC	Cole_Glover71@gmail.com
+380547026924	Rogahn - Wiza	Kaden87@gmail.com
+380378345894	Hintz - Hegmann	Coleman.Cummerata@yahoo.com
+380452213018	Lehner Inc	Lawrence_Ullrich82@gmail.com
+380641644144	Towne, Mayer and Spinka	Roselyn.Howe45@yahoo.com
+380135311015	Pacocha, Douglas and Runte	Lourdes46@hotmail.com
+380723777962	Marquardt - Welch	Shyanne_Keebler@hotmail.com
+380697373472	Paucek - Bartoletti	Marian.Hand93@yahoo.com
+380996529727	Hintz - Sauer	Pasquale_Batz@gmail.com
+380535399240	Heidenreich Group	Josiah_Wintheiser97@hotmail.com
+380022623935	Herman - Baumbach	Gonzalo.Durgan@yahoo.com
+380917704272	Abbott LLC	Ford.Rodriguez30@yahoo.com
+380977574127	Witting and Sons	Domenica22@yahoo.com
+380484364512	Heidenreich - Reilly	Adella_Kshlerin92@gmail.com
+380235342115	Runolfsdottir, Pollich and Wiegand	Vada_Ledner@yahoo.com
+380425033102	Kub, Bins and Schaden	Kailee85@yahoo.com
+380052809253	Stokes, Crooks and Beier	Darby.Hilpert@gmail.com
+380982377182	Corwin - Roberts	Giuseppe_Lemke@gmail.com
+380424684028	Carroll, VonRueden and Larson	Nona79@hotmail.com
+380119249298	Cremin - Casper	Fatima11@gmail.com
+380639255577	Walsh - Renner	Mayra.Bernier11@hotmail.com
+380951189941	Reichel Inc	Dayton72@hotmail.com
+380396577736	Kohler, Oberbrunner and Reynolds	Adaline.Bartell70@gmail.com
+380337139120	Luettgen Inc	Garland11@yahoo.com
+380428934156	Mraz - Jenkins	Moses_Corwin@hotmail.com
+380414809900	Von, Leannon and Satterfield	Eleanore_Kautzer@gmail.com
+380095289433	Sporer, Williamson and Walter	Isaias85@yahoo.com
+380000018020	McClure - Rutherford	Abelardo95@hotmail.com
+380879075729	Ward, Muller and Dibbert	Araceli_Wilkinson16@gmail.com
+380258278885	Swift - Thiel	Moriah59@gmail.com
+380380769520	Veum Inc	Cleora_Mohr86@gmail.com
+380438563584	Huel - Torp	Nyah20@yahoo.com
+380195517057	Leannon Group	Alisa.Turcotte34@yahoo.com
+380421340203	Shanahan - Pollich	Percival_Heller37@gmail.com
+380701921910	Bartoletti Inc	Enrique_Rippin41@hotmail.com
+380313427775	Braun, Hauck and Gislason	Pearline94@hotmail.com
+380268807308	Waelchi - Graham	Nina_MacGyver@gmail.com
+380256490144	Miller LLC	Bernie38@gmail.com
+380087352338	Pagac - Deckow	Leone.Price@yahoo.com
+380137188274	Hickle Group	Candido52@yahoo.com
+380547679928	Collins - Ortiz	Narciso5@hotmail.com
+380909425137	Batz, Homenick and Funk	Burdette_Bartoletti87@yahoo.com
+380916026745	Kautzer and Sons	Cooper47@hotmail.com
+380552049972	Spencer - Schiller	Rosalyn67@yahoo.com
+380338020481	Raynor - Lakin	Jenifer_Luettgen71@hotmail.com
+380883969000	Ferry - Klocko	Herbert_Predovic@gmail.com
+380585457368	Erdman - Murazik	Carissa99@yahoo.com
+380353947453	MacGyver Group	Celestino57@gmail.com
+380133999709	Langosh and Sons	Casper_Kunde63@yahoo.com
+380433023682	Runte, Lynch and Greenfelder	Christelle.Mraz@hotmail.com
+380948482537	Lubowitz - Leuschke	Jerrod_Zieme@yahoo.com
+380452517857	Quigley Group	Bertram_Schaden4@yahoo.com
+380989731209	Kunde - Rath	Weldon.Torphy10@gmail.com
+380576770069	Ruecker - Yost	Reina92@hotmail.com
+380064044584	Romaguera - Gleason	Arjun0@yahoo.com
+380044286614	O'Connell, Jerde and Heathcote	Katelin.Simonis83@hotmail.com
+380209786991	Schamberger - Haag	Brant.Littel@gmail.com
+380463013622	Morar - Miller	Kaya_Breitenberg@hotmail.com
+380143771059	Spencer - Nolan	Shanelle67@gmail.com
+380122821933	Quitzon LLC	Marcelle65@yahoo.com
+380268268697	Hane, Block and O'Hara	Bobbie.Trantow@gmail.com
+380099772733	Langosh, O'Conner and Pollich	Jeff.OKon84@hotmail.com
+380253038783	O'Connell Group	Betty14@gmail.com
+380233628710	Keeling - Nienow	Torrey_Hauck@hotmail.com
+380352091259	Erdman - Hoppe	Kaela95@gmail.com
+380470220571	Abshire and Sons	\N
+380759840961	Barrows - Ledner	\N
+380545488521	Hamill - Rutherford	Opal_Feest65@gmail.com
+380543648174	Kling, Hickle and Stoltenberg	Jacinthe_Purdy@yahoo.com
+380230402603	Dooley Inc	Geovanny74@gmail.com
+380352200009	Jakubowski - Kshlerin	Chad93@hotmail.com
+380503957549	Fadel and Sons	Sienna64@hotmail.com
+380155939552	Donnelly, Roberts and Gutmann	Dasia64@yahoo.com
+380732284353	Harris Inc	Rashawn.Pacocha56@hotmail.com
+380656200010	Braun - Bechtelar	Mollie.Roob54@yahoo.com
+380396222733	Stoltenberg, Rolfson and Kuphal	Dawn16@gmail.com
+380734443388	Lockman - Halvorson	Gage93@gmail.com
+380678866538	Nader LLC	Herminia9@hotmail.com
+380589965139	Hessel, Legros and West	Joanie.King@hotmail.com
+380806512799	Quigley, McGlynn and Goyette	Jennings.Kunze90@yahoo.com
+380857116231	Mante Inc	Rosemary_Hickle@gmail.com
+380843516110	Bosco - Grady	Payton76@yahoo.com
+380966759581	Stark, Bergnaum and Fisher	Ronaldo_Paucek13@gmail.com
+380363107294	Brekke, Larson and Volkman	Hubert28@yahoo.com
+380913649229	Sporer, Crona and Feil	Giuseppe_Ratke@yahoo.com
+380082629869	Emmerich - Crist	Micheal.Kutch@hotmail.com
+380670848824	Tromp and Sons	Bailee.Mueller46@gmail.com
+380160353826	McDermott - Lubowitz	Aron.Sanford11@yahoo.com
+380559018613	Ankunding - Smith	Elmira.Volkman@yahoo.com
+380681669164	Klein, Morar and Kuhn	Leda.Block57@hotmail.com
+380965166577	Gibson - Berge	Lucio_OHara44@hotmail.com
+380839307231	Mante and Sons	Roma.Toy90@gmail.com
+380552181724	Kuphal Group	Ralph.Greenfelder88@gmail.com
+380772074503	Dare LLC	Emmalee_Sawayn@hotmail.com
+380678417500	Yundt and Sons	Zion10@hotmail.com
+380833473725	Grady, Anderson and Wuckert	Heloise_Rodriguez98@yahoo.com
+380981446465	Rolfson, Morissette and Rippin	Vivian_Hand64@gmail.com
+380617854816	Bode - Schamberger	Abner.Swift3@gmail.com
+380883419422	Grant, Abshire and Rowe	Francisco97@hotmail.com
+380886071120	Bogisich Group	Concepcion36@hotmail.com
+380757526567	Anderson LLC	Jarret_Kessler52@hotmail.com
+380656489941	Keeling, Gulgowski and Ortiz	Berniece_Rath37@yahoo.com
+380417437948	Lueilwitz, Kirlin and Hartmann	Perry.Christiansen97@gmail.com
+380973475674	Bednar - Kessler	Adelle.Hintz77@gmail.com
+380630270925	Bailey - Kling	Celestine_Frami@hotmail.com
+380607415160	Heaney, Boehm and Reilly	Millie_Nikolaus88@gmail.com
+380804519975	Cole and Sons	Delfina_Braun@gmail.com
+380090535792	Terry - Hartmann	Tommie21@hotmail.com
+380803435095	Wilderman Group	Leonie.DAmore@hotmail.com
+380875287319	Kuhlman, Kuhlman and Wehner	Talon.Zulauf74@hotmail.com
+380805445158	Stiedemann LLC	Charley63@yahoo.com
+380310432089	Glover Group	Patrick50@hotmail.com
+380602128380	Treutel - Streich	Judd_Denesik@yahoo.com
+380877848187	Dietrich, Cruickshank and D'Amore	Natasha_Mills@hotmail.com
+380443048427	Morissette Inc	Alta.Considine@hotmail.com
+380521109624	Howell - McClure	Lyric59@gmail.com
+380477924111	Block, Willms and Johnson	Kian43@gmail.com
+380226148681	Considine - Bailey	Max.Carter22@gmail.com
+380149462740	Cassin, Mohr and Wiza	Jody95@gmail.com
+380664066409	Kohler - Feest	Elenor_Kutch69@gmail.com
+380074141672	Schimmel Inc	Lawson_Bode12@yahoo.com
+380523107265	Bayer - Cormier	Rickey23@hotmail.com
+380951267687	Olson - Koss	Margret71@gmail.com
+380989087003	Gulgowski - Pollich	Jovany.Crist@gmail.com
+380571373473	Harvey - Hammes	Kraig64@gmail.com
+380343541964	Howell - Kuvalis	Allison.Powlowski@yahoo.com
+380544500415	Glover and Sons	Melisa_Carter10@yahoo.com
+380032400723	Hammes Group	Mallory.Oberbrunner10@hotmail.com
+380541637641	Rogahn Group	Larissa.Bosco35@hotmail.com
+380335842886	Wolff - Parker	Hardy13@hotmail.com
+380184155887	Shanahan - Harvey	Catalina_Schuster@yahoo.com
+380146724973	Shanahan Inc	Cullen76@gmail.com
+380251478241	Wolf, Lesch and Botsford	Minnie95@gmail.com
+380219133181	Stracke Group	Breanna49@hotmail.com
+380550141848	Volkman, Satterfield and Schuppe	Dax65@gmail.com
+380027060428	Glover Group 1	Aniya.Donnelly@gmail.com
+380620497442	Collier, Little and Mayer	Tiffany_Wilkinson@yahoo.com
+380789658845	Grady Inc	Jeanette_Runolfsson69@yahoo.com
+380538914746	Rohan - Orn	Sadye_Durgan@yahoo.com
+380717458312	Cole Group	Joanie_Bergstrom@gmail.com
+380893920132	Yost, Cole and Kautzer	Elinore.Berge@yahoo.com
+380881745367	Jacobson, Padberg and Farrell	Audrey.Krajcik56@yahoo.com
+380781836207	Abbott - Bayer	Maxime18@yahoo.com
+380375475676	Schmitt Inc	Jackson.Boehm@gmail.com
+380200192183	Runte, Kertzmann and Wuckert	Johathan_Lindgren@hotmail.com
+380479929844	Moore - Reynolds	Hillary.Olson@hotmail.com
+380807656385	Baumbach and Sons	Sonia_Smith24@hotmail.com
+380286896407	Kassulke, Grady and Runte	Cale97@yahoo.com
+380098778677	Stokes, Yost and Purdy	Mya21@gmail.com
+380027714502	Robel - Hackett	Carlo80@yahoo.com
+380413835885	Hilpert - Moore	Orlando.Considine@yahoo.com
+380332597297	Borer, Smith and Kunze	Michel38@gmail.com
+380840556747	Gottlieb Group	Leland_Littel@gmail.com
+380011822114	Kovacek LLC	Claudie.White45@gmail.com
+380477011623	Will, Goldner and Ruecker	Enrique.Wilderman6@gmail.com
+380879501448	Kassulke - Rippin	Idella.Doyle@hotmail.com
+380195586517	Kemmer, Reinger and Kirlin	Ivy.Huel21@yahoo.com
+380510709681	Champlin - Veum	Margaret22@yahoo.com
+380331529813	Leannon Group 1	Pierre.Stiedemann@yahoo.com
+380068213597	Farrell Inc	Macey.Brakus@hotmail.com
+380971263323	Beer - Champlin	Willard_Schmidt@yahoo.com
+380764862655	Rowe Group	Kaia.Bins95@yahoo.com
+380103436497	Bednar and Sons	Germaine_Hessel38@yahoo.com
+380290742074	Kulas Group	Sandra.Hartmann@gmail.com
+380840053589	Davis LLC	Lawson_Mraz98@gmail.com
+380097462119	Rutherford, Carroll and Ankunding	Alfred.Pollich89@hotmail.com
+380096837315	Sauer, O'Connell and Conroy	Cassandre_Ullrich70@hotmail.com
+380853689449	Simonis LLC	Nicole86@yahoo.com
+380282244032	Kuhlman, Smitham and Lynch	Abbey_Simonis88@yahoo.com
+380670260558	Daugherty, Skiles and Erdman	Dorthy_Lockman59@gmail.com
+380526570720	Ritchie - Thompson	Darrel59@hotmail.com
+380956141377	Stiedemann, Rutherford and Fadel	Alda.Johnson34@gmail.com
+380552110119	Aufderhar, Beahan and Padberg	Dorthy.Fritsch92@yahoo.com
+380097817521	Streich, O'Kon and Schowalter	Dan.Keebler@yahoo.com
+380983737450	Effertz - Weissnat	Cynthia_Gottlieb77@hotmail.com
+380350694717	Conn, Lubowitz and Lynch	Sincere3@gmail.com
+380342161683	Reichert and Sons	Dudley.Emmerich36@yahoo.com
+380260005986	Jerde - Weimann	Emmalee.Brakus@yahoo.com
+380974817203	Rodriguez LLC	Kenton3@gmail.com
+380672929147	Ritchie and Sons	Lon.Krajcik@yahoo.com
+380973553543	Buckridge - Larson	Graciela.Feil@hotmail.com
+380874929244	Flatley, Klocko and Purdy	Dolly_Huel@hotmail.com
+380291743020	Lehner LLC	Ransom87@yahoo.com
+380817145863	Nikolaus Inc	Bessie_Corkery@yahoo.com
+380656274700	Kunde - Hodkiewicz	Abelardo_Jacobs@hotmail.com
+380465079422	Schoen, Jacobi and Nolan	Jodie.Wilkinson@gmail.com
+380754178929	Shanahan, Heller and Kozey	Braden54@gmail.com
+380586268124	Brown, Ernser and Harris	Alexander19@yahoo.com
+380396438672	VonRueden Inc	Arvilla.Stiedemann@hotmail.com
+380671146794	Blanda - Breitenberg	Rosa.Wilkinson26@yahoo.com
+380465958017	Harvey and Sons	Alfonso.Walker@hotmail.com
+380777199004	Bode - Baumbach	Nannie_Schultz@hotmail.com
+380043548319	Mohr, Vandervort and Schaden	Santos2@hotmail.com
+380608608543	Lesch LLC	Stanford79@hotmail.com
+380377136178	Kling, Wolff and Gerhold	Alvis24@hotmail.com
+380082244321	Kerluke and Sons	Sallie64@hotmail.com
+380941240548	Fay Inc	Luisa.Lueilwitz@gmail.com
+380670405063	Lueilwitz Group	Anahi_Nitzsche48@yahoo.com
+380525215639	Hessel Group	Crystal.Bogan@gmail.com
+380769695841	Kuhlman - Blick	Haskell61@yahoo.com
+380649732684	Brekke LLC	Vance_Fay@gmail.com
+380082400976	Langosh LLC	Shawn66@hotmail.com
+380780221394	Rau, Tremblay and Kiehn	Dejuan.Rowe@yahoo.com
+380808161264	Lesch, Grant and Ledner	Vallie.Ullrich76@yahoo.com
+380637733744	Goyette, Sauer and Wolff	Lorine_Thiel89@gmail.com
+380301031173	Wisozk - Wisozk	Hardy_Boehm@hotmail.com
+380132717212	Lubowitz, Dickinson and Sipes	Jayden.Bauch@gmail.com
+380875603797	Rath Inc	Fay67@hotmail.com
+380258325838	Bernhard, Moore and Satterfield	Hoyt_Prohaska@gmail.com
+380602670284	Medhurst - Witting	Samanta65@hotmail.com
+380426007794	Trantow Inc	Carlotta.Simonis@gmail.com
+380303337892	Luettgen - Hills	Yvette_Wiegand@gmail.com
+380294342588	Turcotte, O'Keefe and Hand	Axel_Runolfsdottir@yahoo.com
+380153454119	McClure, Sipes and Lind	Kaylie_Boyer78@hotmail.com
+380020181741	Franecki, Senger and Yundt	Alexandrea15@yahoo.com
+380089414279	Hermann Group	Leola.Walter7@yahoo.com
+380260947566	Carroll - Marquardt	Garth.Green@gmail.com
+380651728785	Tillman, Streich and Jaskolski	Neva_Mayert69@hotmail.com
+380551119559	Miller - Dare	Al.Keeling98@gmail.com
+380824163468	Mills and Sons	Brennan_Turner@hotmail.com
+380940082966	Boyle - Cole	Bridgette_Keebler@gmail.com
+380107893210	Marquardt Inc	Lysanne_Mann30@gmail.com
+380882517180	Considine, Kutch and Pfannerstill	Howell76@gmail.com
+380582179839	Hudson, Wintheiser and Schiller	Lesly_Marks9@gmail.com
+380142790076	Jakubowski - Lockman	Lindsey40@gmail.com
+380248394145	Langosh - Stroman	Sydni79@gmail.com
+380923797922	Cruickshank - Carter	Connor_Williamson@hotmail.com
+380365592678	Keebler Inc	Milford_Treutel89@gmail.com
+380062230638	Hilll and Sons	Maia_Frami6@yahoo.com
+380237028761	Balistreri Inc	Antwon80@gmail.com
+380773265495	Pollich, Hoppe and Konopelski	Valentina.Grant20@hotmail.com
+380125260473	Mills - Osinski	Alejandrin_Larkin@hotmail.com
+380953295131	Cormier and Sons	Heaven44@yahoo.com
+380592485910	West, Sipes and Kuhn	Dax.McGlynn23@hotmail.com
+380368414641	Gerhold Inc	Rosalind.Frami51@hotmail.com
+380458411710	Kunze LLC	Gideon15@gmail.com
+380211303044	Hauck, Lakin and Nicolas	Cullen.Davis77@hotmail.com
+380785271870	Thiel and Sons	Chanel_Mitchell78@yahoo.com
+380351336176	Lang Inc	Evert_Lind@yahoo.com
+380986492048	Ortiz - Stanton	Eliane.Roob91@gmail.com
+380949848371	Haley, Murphy and McGlynn	Brandy.Ruecker@yahoo.com
+380189679268	Abbott Group	\N
+380876172546	Mills LLC	Karley_Pfannerstill@yahoo.com
+380441218457	Crooks - Block	Alexys_Schaden79@yahoo.com
+380996010861	Lynch, Johnson and Beahan	Natasha_Predovic75@hotmail.com
+380275041217	Cormier, McDermott and Kris	Mario_Flatley@hotmail.com
+380089175773	Hartmann Inc	Victor_Stanton@hotmail.com
+380214135517	McCullough Inc	Myrtie23@gmail.com
+380684878315	Volkman, Cronin and Windler	Catharine_Dicki@gmail.com
+380514498637	Lind, Huels and D'Amore	Glenda.Yost48@hotmail.com
+380336404815	Windler, Connelly and Wintheiser	Vincenza29@yahoo.com
+380930802439	Weber, Emmerich and Fay	Opal.Renner@gmail.com
+380454286777	Bins - Littel	Darian49@yahoo.com
+380697618340	Cormier, Hansen and Brown	Alexandre.Larkin38@hotmail.com
+380292819110	Walker - Krajcik	Daphne_Reichert12@hotmail.com
+380029069199	Koepp LLC	Shea.Conroy@yahoo.com
+380171170671	Miller LLC 1	Jolie_Satterfield26@hotmail.com
+380290660538	Feil, Windler and Parker	Therese_Mohr18@yahoo.com
+380320676661	Langworth, Fisher and Harris	Dora.Legros70@gmail.com
+380425635725	Kemmer, Rutherford and Shields	Rory_Abbott@hotmail.com
+380508796232	Rippin and Sons	Leanna_Bayer64@yahoo.com
+380031541692	Schulist, Wyman and Moen	Savanah40@hotmail.com
+380259514788	Stracke - Leannon	Holly77@hotmail.com
+380833158559	Rutherford, Weissnat and Wilkinson	Manley_Wehner@hotmail.com
+380136718871	Bauch - Cummerata	Brent_Ebert10@gmail.com
+380918985046	Treutel Group	Lawrence.Tremblay41@hotmail.com
+380634875802	Morissette Group	Charity_Crooks76@hotmail.com
+380485493165	Dietrich and Sons	Lilliana_Davis@gmail.com
+380127709791	Weissnat - Kessler	Ivah90@gmail.com
+380190587176	Farrell - Littel	Art_Grady@hotmail.com
+380042744723	Daugherty - Lesch	Heath_Wuckert@yahoo.com
+380763953005	Keebler - Feil	Lewis.Jacobs@yahoo.com
+380064456884	Schmitt, O'Reilly and Daniel	Adalberto56@hotmail.com
+380425289655	Koss, Blick and Larson	Shakira.Hammes@gmail.com
+380090627686	Glover Group 2	Kiley.Williamson74@hotmail.com
+380605529266	Kihn, Kunze and Wolff	Ike_Pagac@gmail.com
+380291505393	Reynolds Group	Christina13@hotmail.com
+380459731803	Leannon, Wolff and Witting	Vivian.Wintheiser@gmail.com
+380700134691	Buckridge, Mante and Kuhn	Nella_Fay3@yahoo.com
+380797848829	Zemlak, Marvin and Kulas	Kailey.Klein38@yahoo.com
+380712706943	Franecki, Grimes and Kirlin	Laney24@hotmail.com
+380306795852	Auer, Dietrich and Streich	Alberta.Heidenreich10@gmail.com
+380278265347	Purdy, Bins and Hahn	Jade93@hotmail.com
+380897420025	Armstrong LLC	Dorothea11@yahoo.com
+380959086386	Bogan, Bayer and McGlynn	Noe.King44@gmail.com
+380985988047	Bechtelar Group	Rosalyn59@gmail.com
+380666660875	Aufderhar - Reynolds	Marvin8@hotmail.com
+380472175683	Littel, Smith and Murray	Norberto85@yahoo.com
+380731845680	Yost - Kunze	Alvah.Keebler@hotmail.com
+380435161620	Kertzmann, Buckridge and Koch	Tobin.Feil27@gmail.com
+380369459962	Powlowski, Johns and Borer	Leonardo_Lind79@hotmail.com
+380493728603	Huels, Schultz and O'Conner	Javon.Howe@yahoo.com
+380324261464	Batz - Price	Peggie51@hotmail.com
+380618990554	Kuhn - Jast	Thalia.Rosenbaum@hotmail.com
+380990834163	Lynch Group	Crystel27@yahoo.com
+380710115237	Kassulke - Koss	Imani.Frami10@yahoo.com
+380340152531	Bauch - Romaguera	Anibal_Osinski@hotmail.com
+380070514158	Jacobson - Mayert	Cedrick.Hahn85@gmail.com
+380684364894	Halvorson - Hand	Carmelo_Lakin@yahoo.com
+380742374341	Frami, Mante and Schaefer	Camryn71@gmail.com
+380152524889	Welch - Kovacek	Arno.Bahringer@hotmail.com
+380605009122	Torp - Kunde	Omari_Hyatt93@gmail.com
+380943562107	Windler Inc	Juwan.Gleason@yahoo.com
+380508032469	Borer, Lehner and Hilpert	Heber.Kuphal63@yahoo.com
+380830079759	Wolf, Goldner and Kihn	Dejon.Pagac52@yahoo.com
+380250526697	Sanford and Sons	Damon_Kuphal@yahoo.com
+380966094871	Kessler Group	Karolann.Willms@hotmail.com
+380438015538	Lind LLC	Everett86@gmail.com
+380964231746	McClure, Braun and Hauck	Missouri_Flatley18@yahoo.com
+380017019159	Williamson - McClure	Kennith.Lubowitz3@gmail.com
+380762716065	Schimmel Inc 1	Jaunita.Strosin2@hotmail.com
+380796721342	Miller, Bauch and Goyette	Marjorie_Welch17@gmail.com
+380712454650	Mosciski - Hudson	Holly.Bartoletti@yahoo.com
+380727133566	Harris and Sons	Durward68@yahoo.com
+380971326173	Emmerich - Nader	Rey_OConner@gmail.com
+380097473006	Haag, Dooley and Spinka	Modesto_Tillman85@gmail.com
+380796283461	Haley Inc	Jolie_Yost82@gmail.com
+380094722224	Watsica - Will	Donna.Schneider81@yahoo.com
+380604190107	Dooley, Lakin and Rippin	Sarah21@yahoo.com
+380125950410	Pfeffer - Glover	Madilyn.Cole@gmail.com
+380894946874	Terry, Murphy and Nicolas	Darlene_Raynor60@gmail.com
+380414887026	Medhurst - Turcotte	Aida_Herman3@yahoo.com
+380244176473	Mohr Group	Jacey_West68@yahoo.com
+380715749114	Gerlach - Kertzmann	Arnaldo.Ferry38@hotmail.com
+380173035897	Lynch, Kuvalis and Schamberger	Beulah89@gmail.com
+380075999754	Bogisich and Sons	Vance56@gmail.com
+380920951777	Beatty and Sons	Gene40@yahoo.com
+380421047703	Gutmann - Emmerich	Flossie.Paucek88@yahoo.com
+380774793044	Lockman, Kulas and Leffler	Elnora58@hotmail.com
+380455601532	Jacobson, Ernser and Walter	Michel.Grimes26@hotmail.com
+380645816136	Lakin LLC	Amos.Okuneva72@gmail.com
+380076393505	Leannon - Koch	Maximus_Boehm@hotmail.com
+380974034148	Prosacco, Orn and Koss	Maudie_Kerluke@yahoo.com
+380838617873	Feest - Thiel	Myron.Morar@hotmail.com
+380705549684	Schimmel - Runte	Clementina65@gmail.com
+380832494477	Bauch - Pacocha	Dejah80@hotmail.com
+380885745681	Smitham - Schaefer	Velva_OReilly@yahoo.com
+380906712901	Hermiston and Sons	Tianna69@gmail.com
+380816422691	Terry and Sons	Kaylie.Macejkovic26@yahoo.com
+380148882254	Leuschke LLC	Bennie94@yahoo.com
+380474390721	Trantow - Nikolaus	Lucas.Spinka0@yahoo.com
+380622491616	Mertz and Sons	Arnulfo70@hotmail.com
+380059998654	Mann - Murray	Electa70@hotmail.com
+380979772690	Kessler - Fahey	Cassidy_Ledner@hotmail.com
+380992709705	Schultz and Sons	Dayne_Stokes24@hotmail.com
+380335325463	Willms - Wiegand	Marjorie.Jones@gmail.com
+380048648527	Welch, Carroll and Quitzon	Reinhold.Hudson10@hotmail.com
+380540828196	Kautzer - Nader	Earnestine.Mohr@gmail.com
+380385841100	Russel, Berge and Tremblay	Marguerite16@hotmail.com
+380196501344	Murazik - Hudson	Mona.Greenholt54@yahoo.com
+380820051266	Greenfelder Inc	Karlie86@gmail.com
+380614676862	Bednar, King and Christiansen	Lillie.Botsford39@hotmail.com
+380933842243	Hegmann, Ortiz and Osinski	Dereck.Lockman5@hotmail.com
+380490237535	Price, Doyle and Monahan	Domenick58@hotmail.com
+380482673567	King LLC	Lew_Romaguera@gmail.com
+380656260327	Murazik LLC	Rupert88@yahoo.com
+380176627015	Durgan - Hauck	Raquel.Hodkiewicz@gmail.com
+380215852382	Block, Wiegand and Trantow	Kelli_Emmerich73@gmail.com
+380818132667	Herzog LLC	Ellie.Swift@hotmail.com
+380340889356	Spinka and Sons	Hertha.Miller10@hotmail.com
+380282561965	Graham and Sons	Nellie.Dickens@yahoo.com
+380871356411	Powlowski, Walter and Rath	Maegan.Schinner31@hotmail.com
+380541979992	Ledner - Friesen	Orin_Kiehn@gmail.com
+380069552768	Kris - Hodkiewicz	Gust3@hotmail.com
+380208085230	Grady - Wuckert	Katharina3@hotmail.com
+380665303272	Hartmann, Dach and Dicki	Ambrose44@gmail.com
+380951367283	Beatty LLC	Demetris.Rolfson@gmail.com
+380323742065	Leannon Group 2	Nicholas88@yahoo.com
+380222521243	O'Conner - Halvorson	Mallie83@yahoo.com
+380402390339	Kuvalis LLC	Marilyne_Gleichner@yahoo.com
+380986206608	Kiehn, Sanford and Ruecker	Tracey0@yahoo.com
+380190879269	Walker - Waters	Julie.Huels@yahoo.com
+380336324444	Toy LLC	Jaclyn_Macejkovic@gmail.com
+380552761818	Botsford - Cronin	Russ.Streich@hotmail.com
+380113179900	Crooks - Altenwerth	Bret_Medhurst@gmail.com
+380699401738	Koch LLC	Reilly19@gmail.com
+380761524164	Kassulke Inc	Timmothy.Thiel43@yahoo.com
+380211182523	Heller - Fadel	Frida.Runte@hotmail.com
+380681655859	Gleichner Inc	Dorris_Terry@hotmail.com
+380354161115	Ryan, Hansen and Cartwright	Andy_Treutel@gmail.com
+380126881683	Rosenbaum LLC	Janie_Rohan@yahoo.com
+380930259708	Huel, Schinner and O'Connell	Jasmin68@hotmail.com
+380150525129	Larkin - Bode	Viola_Howell@hotmail.com
+380379514721	Zulauf Inc	Flo.Klein67@gmail.com
+380793293628	Koelpin, Weimann and Barrows	Gennaro99@yahoo.com
+380881880137	Bailey Group	Norma74@gmail.com
+380989481792	Halvorson - Yundt	Kelsie.Hayes32@gmail.com
\.


--
-- TOC entry 4948 (class 0 OID 16539)
-- Dependencies: 223
-- Data for Name: invoice; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.invoice (invoice_id, counterparty_name, storage_keeper_phone, storage_id, date, total_price, type) FROM stdin;
1210	Schowalter - Schinner	+380327675624	1814	2024-03-11	8850.22	out
1211	Shanahan - Pollich	+380284663850	1644	2024-09-16	6269.31	in
1212	Kuhlman, Kuhlman and Wehner	+380157457650	1744	2024-10-01	1354.01	in
1213	Miller - Dare	+380418999050	1976	2023-09-17	8543.25	out
1214	Kessler - Fahey	+380043750390	1832	2023-04-13	3918.99	out
1215	Ledner - Friesen	+380591438907	1610	2023-12-15	1732.37	in
1216	Treutel Group	+380810597397	1717	2024-02-15	6333.39	in
1217	Miller LLC 1	+380542614825	1528	2023-08-20	4842.62	in
1218	Sanford and Sons	+380949502137	1860	2023-08-13	3638.36	out
1219	Simonis LLC	+380110817184	1571	2024-08-05	7143.51	out
1220	Schoen, Jacobi and Nolan	+380766212984	1778	2024-06-08	1177.02	out
1221	Gibson - Berge	+380672975313	1561	2023-12-12	1848.70	out
1222	Stracke - Leannon	+380581615973	1516	2023-02-13	6060.94	out
1223	Bins - Littel	+380625168742	1547	2023-12-04	9740.23	out
1224	Armstrong LLC	+380859936324	1722	2024-02-18	8689.49	in
1225	Hammes Group	+380349377957	1990	2023-08-04	3794.69	out
1226	Kertzmann, Buckridge and Koch	+380489885886	1723	2023-06-23	7543.23	out
1227	Bode - Baumbach	+380795615091	1958	2023-03-07	3879.57	out
1228	Feil, Windler and Parker	+380428964690	1545	2023-12-23	1763.62	out
1229	McCullough Inc	+380353779966	1629	2024-06-22	2306.01	out
1230	Raynor - Lakin	+380131925978	1845	2023-10-20	5874.22	in
1231	Dooley, Lakin and Rippin	+380200078979	1779	2024-04-01	4026.33	in
1232	Miller, Bauch and Goyette	+380884136165	1882	2023-07-10	9445.47	in
1233	Leannon, Wolff and Witting	+380419222035	1709	2023-04-01	9131.84	in
1234	Considine - Bailey	+380788058521	1639	2022-11-04	3618.44	in
1235	Yost - Kunze	+380470406120	1665	2023-07-09	5808.51	out
1236	Kuhlman - Blick	+380006100448	1513	2024-05-02	7150.64	out
1237	Reynolds Group	+380642817268	1951	2024-09-23	9930.02	in
1238	McClure, Braun and Hauck	+380216388882	1863	2023-12-12	5294.31	in
1239	Aufderhar - Reynolds	+380146781743	1685	2023-11-29	1380.51	out
1240	Yost, Cole and Kautzer	+380086498598	1729	2024-03-11	6532.55	in
1241	Windler Inc	+380694808011	1684	2023-03-27	3028.12	out
1242	Considine - Bailey	+380970596100	1704	2022-11-15	8848.82	in
1243	Kemmer, Rutherford and Shields	+380617989751	1620	2024-08-27	7232.24	in
1244	Gibson - Berge	+380383316304	1706	2023-11-14	6657.54	out
1245	Kautzer - Nader	+380847468056	1504	2024-02-11	8064.81	out
1246	Hintz - Sauer	+380959542527	1982	2024-01-28	3225.44	out
1247	Flatley, Klocko and Purdy	+380038853718	1736	2022-10-27	7947.39	out
1248	Barrows - Ledner	+380995175965	1624	2023-05-28	4399.81	out
1249	Ritchie - Thompson	+380080388574	1796	2024-07-07	3306.45	in
1250	Gottlieb Group	+380270780830	1574	2023-03-05	5563.60	in
1251	Schultz and Sons	+380797316115	1733	2023-05-27	1385.66	out
1252	Huel, Schinner and O'Connell	+380735628666	1896	2023-08-10	9764.49	out
1253	Towne, Mayer and Spinka	+380760846680	1751	2024-06-22	2429.53	out
1254	Gleichner Inc	+380797060959	1914	2022-12-22	4780.96	in
1256	Brown, Ernser and Harris	+380146781743	1842	2023-04-09	6333.47	out
1257	McDermott - Lubowitz	+380300871886	1842	2022-12-22	1392.31	in
1258	Terry - Hartmann	+380237366998	1657	2023-07-20	6865.53	in
1259	Koss, Blick and Larson	+380501600513	1595	2023-01-26	3719.91	in
1260	Turcotte, O'Keefe and Hand	+380870603474	1936	2024-03-03	9180.52	out
1261	Stokes, Yost and Purdy	+380055746349	1999	2022-11-29	2389.86	in
1262	Windler Inc	+380869534011	1824	2023-11-23	4991.25	out
1263	Kunde - Rath	+380812566394	1754	2023-06-26	9894.16	in
1264	Yost, Cole and Kautzer	+380714140700	1780	2024-02-02	9407.40	in
1265	Sporer, Crona and Feil	+380931890195	1695	2024-03-26	8279.86	in
1266	Ledner - Friesen	+380829240717	1853	2023-01-22	6163.30	out
1267	Ritchie and Sons	+380965982395	1862	2023-01-12	1413.54	out
1268	Hilll and Sons	+380354388770	1832	2024-08-02	3753.04	in
1269	Boyle - Cole	+380566208359	1703	2024-04-29	3711.51	in
1270	Effertz - Weissnat	+380364997432	1566	2023-03-18	1920.73	out
1271	Bauch - Romaguera	+380459100374	1716	2023-01-17	4910.83	in
1272	Trantow - Nikolaus	+380055407484	1643	2024-01-26	8188.25	out
1273	Leannon Group 2	+380629244238	1739	2022-11-14	8242.34	in
1274	Lehner Inc	+380855840424	1837	2024-10-09	1703.59	out
1275	Batz, Homenick and Funk	+380151211879	1729	2023-06-04	6525.38	out
1276	Spinka and Sons	+380585297393	1780	2023-09-25	9797.47	out
1277	Sanford and Sons	+380887185308	1969	2023-09-16	6551.58	in
1278	Nader LLC	+380814923310	1859	2023-10-19	3424.78	in
1279	Botsford - Cronin	+380586218792	1694	2023-07-14	9971.41	in
1280	Murazik - Hudson	+380213959370	1910	2024-05-19	8070.08	out
1281	Hammes Group	+380210849018	1878	2023-06-20	8438.79	out
1282	Huel, Schinner and O'Connell	+380778033448	1664	2024-05-31	6021.82	in
1283	Erdman - Hoppe	+380973076459	1776	2024-04-02	6445.94	in
1284	McClure, Sipes and Lind	+380814636468	1662	2023-05-22	5016.21	out
1285	Kemmer, Rutherford and Shields	+380928116288	1945	2024-05-16	7656.16	out
1286	Waelchi - Graham	+380241127335	1848	2023-11-04	3967.10	in
1287	Durgan - Hauck	+380999719096	1620	2024-03-06	1979.81	in
1288	Watsica - Will	+380617117083	1762	2024-09-22	5301.26	out
1289	Runte, Lynch and Greenfelder	+380574606149	1596	2024-03-24	4024.76	in
1290	Harvey - Hammes	+380772231114	1515	2023-03-07	7850.22	out
1291	Beatty LLC	+380662558582	1843	2022-12-22	2442.13	in
1292	Glover Group 1	+380632576339	1865	2023-03-10	5357.46	out
1293	Lind LLC	+380751217885	1678	2022-11-28	5451.35	out
1294	Graham and Sons	+380688027764	1822	2023-01-14	3839.85	in
1295	Lueilwitz Group	+380756196822	1683	2023-06-14	1038.84	in
1296	Feil, Windler and Parker	+380627102664	1863	2023-04-12	9092.59	in
1297	Hermiston and Sons	+380341595095	1957	2023-07-25	8408.92	in
1298	Collier, Little and Mayer	+380830791020	1938	2023-03-21	9766.97	in
1299	Harris Inc	+380527116051	1568	2023-04-23	8589.52	in
1300	Leannon Group 1	+380663981717	1667	2022-12-28	9113.38	in
1301	Gleichner Inc	+380348007042	1627	2023-03-02	4584.78	out
1302	Effertz - Weissnat	+380585818647	1654	2023-04-14	1826.03	in
1303	Morissette Group	+380277778144	1724	2023-01-23	5823.87	out
1304	Rippin and Sons	+380749717101	1802	2024-10-19	2797.47	in
1305	Hermann Group	+380327675624	1931	2023-09-05	7286.61	in
1306	Veum Inc	+380113506397	1731	2023-07-03	5253.25	out
1307	Kovacek LLC	+380583151063	1738	2023-08-09	9374.40	in
1308	Williamson - McClure	+380585297393	1879	2023-06-08	5091.37	out
1309	Schamberger - Haag	+380103595896	1588	2024-05-11	6800.56	in
1310	Bailey - Kling	+380279265665	1820	2023-11-21	2771.52	in
1311	Donnelly, Roberts and Gutmann	+380681755990	1827	2023-03-02	2036.70	out
1312	Rowe Group	+380774020045	1629	2023-07-26	9610.40	in
1313	Champlin - Veum	+380292042899	1564	2024-05-20	7471.15	out
1314	Bogisich and Sons	+380308766884	1909	2023-01-16	8577.98	out
1315	Rau, Tremblay and Kiehn	+380998539812	1898	2022-12-26	1542.23	in
1316	Windler, Connelly and Wintheiser	+380620137078	1827	2024-07-14	1011.25	in
1317	Runolfsdottir, Pollich and Wiegand	+380751758633	1848	2024-02-25	1147.34	out
1318	Heaney, Boehm and Reilly	+380821132871	1811	2024-03-05	9576.84	out
1319	Rogahn - Wiza	+380721066625	1895	2024-05-24	7497.84	out
1320	Bernhard, Moore and Satterfield	+380897908118	1733	2023-09-25	6040.85	in
1321	Volkman, Satterfield and Schuppe	+380039420486	1523	2024-06-14	8539.93	in
1322	Herzog LLC	+380636741235	1767	2022-12-04	3280.80	in
1323	Rodriguez LLC	+380666158505	1761	2023-05-01	2715.00	out
1324	Brekke LLC	+380879457494	2001	2024-02-10	9113.58	out
1325	Champlin - Veum	+380628039718	1832	2024-09-12	6786.70	in
1326	Bosco - Grady	+380658106510	1550	2023-08-09	2187.23	out
1327	Keeling, Gulgowski and Ortiz	+380452260764	1553	2022-11-07	4694.77	in
1328	Stiedemann, Rutherford and Fadel	+380376963270	1785	2023-03-03	6673.27	in
1329	Howell - Kuvalis	+380546686040	1919	2023-08-03	2946.55	out
1330	Koelpin, Weimann and Barrows	+380103180146	1530	2023-08-17	1888.13	in
1331	Collier Inc	+380553496559	1863	2024-03-16	3209.37	in
1332	Lubowitz - Leuschke	+380162324345	1618	2023-06-30	7945.58	out
1333	Kub, Bins and Schaden	+380443882387	1702	2024-10-14	9435.00	out
1334	Heidenreich Group	+380591899243	1842	2024-04-28	3854.73	in
1335	Stracke Group	+380755282619	1933	2024-08-07	8830.34	out
1336	Marquardt Inc	+380910889105	1867	2023-09-21	8423.29	out
1337	Dietrich, Cruickshank and D'Amore	+380064008876	1526	2022-12-19	3757.57	out
1338	Dooley, Lakin and Rippin	+380108324450	1547	2022-11-06	5444.54	out
1339	Kassulke, Grady and Runte	+380606272487	1680	2024-02-04	8151.00	out
1340	Huel, Schinner and O'Connell	+380821359775	1605	2024-06-21	9824.53	in
1341	Rau, Tremblay and Kiehn	+380127485742	1780	2023-02-06	1678.03	out
1342	Ritchie - Thompson	+380277138684	1504	2024-04-21	7488.39	in
1343	Jacobson, Ernser and Walter	+380861811310	1922	2022-11-27	9084.32	in
1344	Gulgowski - Pollich	+380844452985	1646	2023-09-08	5237.94	in
1345	Ledner, Bartoletti and Wuckert	+380170031782	1889	2024-07-26	4820.14	in
1346	Welch, Carroll and Quitzon	+380359889004	1676	2023-10-04	2975.19	out
1347	Considine - Bailey	+380395299999	1827	2024-01-16	4819.80	out
1348	Braun, Hauck and Gislason	+380870157763	1720	2023-01-10	7636.97	in
1349	Lesch, Grant and Ledner	+380063091956	1608	2023-11-26	6002.93	out
1350	Yundt and Sons	+380045797287	1637	2023-09-22	4139.48	in
1351	Quigley, McGlynn and Goyette	+380391243678	1734	2024-07-11	6627.65	out
1352	Quigley Group	+380439461471	1533	2023-02-11	8126.48	out
1353	Raynor - Lakin	+380971946007	1892	2022-12-13	7341.81	in
1354	Miller LLC	+380584495691	1623	2023-07-03	9065.17	out
1355	Graham and Sons	+380800173906	1843	2023-08-15	1502.57	out
1356	Mills - Osinski	+380474972934	1793	2023-08-06	8831.50	out
1357	Tromp and Sons	+380629524411	1543	2024-06-05	3296.44	out
1358	Brekke, Larson and Volkman	+380047174009	1834	2023-03-18	3648.68	out
1359	Anderson LLC	+380106418887	1746	2023-04-11	2710.89	in
1360	Towne, Mayer and Spinka	+380191663620	1520	2023-07-07	8339.99	out
1361	Schoen, Jacobi and Nolan	+380080388574	1716	2023-05-11	4957.95	in
1362	Powlowski, Johns and Borer	+380781089361	1539	2023-10-10	7375.61	in
1363	Howell - McClure	+380345389424	1859	2024-02-25	5928.32	out
1364	Stracke Group	+380821658934	1852	2023-06-25	6208.92	out
1365	Beer - Champlin	+380791358592	1644	2024-02-13	7970.87	in
1366	Simonis LLC	+380043750390	1940	2023-02-17	1034.71	out
1367	Crooks - Block	+380774020045	1713	2024-01-19	5921.83	in
1368	Gottlieb Group	+380577019139	1888	2023-04-05	7701.28	in
1369	Dare LLC	+380313305331	1700	2023-05-01	4109.85	in
1370	McClure - Rutherford	+380465732311	1728	2023-01-28	1560.64	out
1371	Franecki, Senger and Yundt	+380640311748	1938	2023-08-04	5722.16	out
1372	Lynch, Johnson and Beahan	+380258303711	1727	2023-03-06	6037.79	in
1373	Considine - Bailey	+380760316297	1794	2022-11-14	7420.74	out
1374	Terry - Hartmann	+380160399603	1651	2024-02-18	4076.70	out
1375	Abbott - Bayer	+380193313588	1849	2023-03-25	5054.61	in
1376	Carroll, VonRueden and Larson	+380369500155	1986	2024-01-02	3310.39	in
1378	Rutherford, Weissnat and Wilkinson	+380656855607	1665	2023-03-17	7385.07	out
1379	Bailey Group	+380239253431	1519	2024-06-30	5355.91	in
1380	Huel - Torp	+380013002392	1591	2024-07-14	8715.59	in
1381	Schultz and Sons	+380476432234	1968	2023-08-06	8810.51	in
1382	Stracke - Leannon	+380743180055	1572	2022-12-17	4466.60	in
1383	Kerluke and Sons	+380067162067	1749	2023-06-12	2493.98	out
1384	Block, Wiegand and Trantow	+380978135647	1767	2024-06-16	2214.24	out
1385	Boyle - Cole	+380367466104	1791	2023-07-25	2561.14	out
1386	Abbott Group	+380278478895	1871	2024-03-26	5329.15	out
1387	Dietrich, Cruickshank and D'Amore	+380160703104	1923	2024-07-20	4855.41	out
1388	Volkman, Cronin and Windler	+380169354685	1851	2023-02-27	4036.55	out
1389	Kuvalis LLC	+380194478208	1912	2024-07-27	7899.64	in
1390	Feest - Thiel	+380043750390	1749	2024-05-01	7087.38	in
1391	Aufderhar - Reynolds	+380152855366	1881	2023-06-28	8613.07	out
1377	Williamson - McClure	\N	1961	2024-02-20	3859.47	in
1393	McClure, Sipes and Lind	+380201509906	1899	2023-06-05	9976.36	in
1394	Schowalter - Schinner	+380949652801	1976	2023-04-14	7134.11	out
1395	Torp - Kunde	+380647294271	1897	2023-05-30	7944.55	out
1396	Schmitt, O'Reilly and Daniel	+380580639248	1801	2024-07-14	5551.09	in
1397	Blick - Morar	+380662558582	1802	2023-03-11	6910.43	in
1398	Watsica - Will	+380913243911	1995	2023-08-25	1657.07	in
1399	Abbott - Bayer	+380164024188	1735	2023-08-14	5682.27	in
1400	Kunze LLC	+380790565295	1532	2023-09-29	5937.33	in
1401	Lueilwitz Group	+380660043840	1995	2024-10-20	1117.06	out
1402	Jerde - Weimann	+380822306269	1965	2022-10-27	1877.81	out
1403	Schimmel Inc 1	+380247337576	1832	2022-12-06	1124.44	out
1404	Kling, Hickle and Stoltenberg	+380746920564	1548	2023-12-29	1162.71	out
1405	Gutmann - Emmerich	+380071382109	1920	2023-11-09	6696.96	out
1406	Glover and Sons	+380503691965	1760	2024-01-22	5356.67	in
1407	Schimmel Inc 1	+380243969096	1755	2023-04-12	6909.81	in
1408	Keebler - Feil	+380218749333	1722	2023-11-01	6127.16	out
1409	Dooley Inc	+380887449438	1725	2024-02-27	7105.94	in
1410	Sauer, O'Connell and Conroy	+380198099497	1701	2023-12-19	1957.73	in
1411	Runolfsdottir, Pollich and Wiegand	+380837379359	1557	2022-12-09	7494.65	out
1412	Pacocha, Douglas and Runte	+380308766884	1981	2024-06-15	8816.45	out
1413	Kertzmann, Buckridge and Koch	+380015355508	1824	2023-04-20	5589.21	out
1414	Bogisich Group	+380418813019	1517	2022-12-21	1069.35	in
1415	Dooley, Lakin and Rippin	+380652312958	1801	2023-09-15	4732.03	out
1416	Boyle - Cole	+380230249090	1916	2024-09-01	1504.08	out
1417	Lockman - Halvorson	+380949502137	1771	2023-02-12	5359.88	in
1418	Kunde - Hodkiewicz	+380437270872	1873	2023-02-14	9334.83	out
1419	Hessel Group	+380185906287	1966	2024-06-28	7361.73	in
1420	Yundt and Sons	+380508748071	1648	2023-06-29	6150.47	out
1421	Yost - Kunze	+380263837665	1655	2023-01-25	6391.96	out
1422	Marquardt - Welch	+380772491933	1956	2024-02-13	2269.62	out
1423	Willms - Wiegand	+380254187094	1946	2024-01-13	2460.99	in
1424	Kemmer, Reinger and Kirlin	+380928922217	1731	2023-11-26	5289.97	in
1425	Paucek - Bartoletti	+380349330957	1896	2024-08-28	5010.10	in
1426	Kemmer, Rutherford and Shields	+380582554695	1633	2024-08-09	5584.28	in
1427	Borer, Lehner and Hilpert	+380328023671	1675	2024-10-22	5107.16	in
1428	Luettgen Inc	+380094573945	1683	2024-10-06	7966.82	in
1429	Balistreri Inc	+380419222035	1676	2024-06-11	1472.85	out
1430	Yost, Cole and Kautzer	+380538574174	1519	2023-02-22	1311.94	out
1431	Turcotte, O'Keefe and Hand	+380304132276	1547	2024-05-12	3573.11	in
1432	Rowe Group	+380491759765	1873	2024-10-25	5871.64	in
1433	Ledner - Friesen	+380274015906	1834	2023-12-01	8838.24	out
1434	Bartell Inc	+380098547994	1593	2024-05-20	9082.82	out
1435	Dooley Inc	+380546686040	1821	2023-02-25	4202.30	in
1436	Braun - Bechtelar	+380859936324	1528	2023-05-27	8087.08	out
1437	Abbott LLC	+380139535921	1796	2022-12-16	5046.29	out
1438	Morar - Miller	+380043907096	1831	2023-04-07	3003.74	in
1439	Ryan, Hansen and Cartwright	+380574707509	1515	2024-05-19	5610.50	out
1440	Leannon, Wolff and Witting	+380331860980	1800	2024-06-26	8830.89	out
1441	Rohan - Orn	+380584495691	1619	2023-02-18	6337.23	out
1442	Kessler Group	+380347318735	1930	2024-03-29	1084.92	in
1443	Cormier and Sons	+380580401438	1558	2023-04-29	3735.22	in
1444	Lind, Huels and D'Amore	+380216388882	1915	2024-05-24	2917.83	out
1445	Hamill - Rutherford	+380627658490	1686	2024-07-07	2205.75	in
1446	Franecki, Senger and Yundt	+380757026952	1729	2023-09-07	2642.35	out
1447	Effertz - Weissnat	+380418834923	1587	2023-09-05	3021.27	out
1448	Witting and Sons	+380438405407	1929	2023-06-20	3108.80	in
1449	Luettgen Inc	+380116931364	1647	2024-05-18	7859.79	out
1450	Powlowski, Johns and Borer	+380990879925	1686	2023-08-08	4643.10	out
1451	Kunde - Hodkiewicz	+380909540554	1780	2023-07-05	4351.78	in
1452	Schoen, Jacobi and Nolan	+380082349636	1844	2022-11-02	8488.88	in
1453	Collins - Ortiz	+380742139134	1545	2023-10-19	8964.48	in
1454	Rodriguez LLC	+380353987610	1579	2024-06-28	6567.62	out
1455	Weissnat - Kessler	+380353987610	1699	2024-01-12	1982.44	in
1456	Von, Leannon and Satterfield	+380106541515	1794	2024-02-20	1415.63	in
1457	Kuhlman - Blick	+380617989751	1645	2023-01-04	4337.17	in
1458	Miller LLC 1	+380050706680	1568	2023-12-07	1557.34	out
1459	Stokes, Crooks and Beier	+380580639248	1633	2023-01-08	5048.93	out
1460	Lakin LLC	+380883779713	1847	2023-11-24	7917.00	out
1461	Kuphal Group	+380325870740	1528	2023-03-23	1463.30	in
1462	Hudson, Wintheiser and Schiller	+380359889004	1733	2023-02-05	8358.17	out
1463	Reichert and Sons	+380010483815	1637	2023-10-19	3726.89	out
1464	Thiel and Sons	+380723762990	1635	2023-08-06	4072.37	out
1465	Bailey Group	+380428716882	1900	2024-05-13	9740.48	out
1466	Lakin LLC	+380387923334	1957	2023-12-13	1800.21	out
1467	Von, Leannon and Satterfield	+380418813019	1573	2024-09-27	3412.38	out
1468	Langosh LLC	+380594460273	1829	2023-09-10	3421.65	in
1469	Schulist, Wyman and Moen	+380127660790	1812	2024-01-06	6338.01	in
1470	Hudson, Wintheiser and Schiller	+380739819586	1795	2024-05-18	1713.94	out
1471	Schimmel Inc 1	+380179871999	1945	2024-02-05	9782.49	out
1472	Sporer, Williamson and Walter	+380060676980	1881	2024-06-26	2462.59	out
1473	Mills and Sons	+380291245798	1585	2024-09-05	2562.21	out
1474	O'Conner - Halvorson	+380112024854	1698	2023-02-15	1948.47	in
1475	Marquardt - Welch	+380779982740	1878	2024-04-26	1307.67	out
1476	Lynch, Kuvalis and Schamberger	+380870157763	1935	2023-01-30	4423.61	in
1477	Kuhlman - Blick	+380291155779	1811	2022-12-29	6731.59	in
1478	Rosenbaum LLC	+380089645156	1736	2023-01-16	9815.64	in
1479	Ritchie and Sons	+380754829835	1782	2024-09-04	9321.79	out
1480	O'Conner - Halvorson	+380897908118	1878	2024-02-02	3350.77	in
1481	Collier, Little and Mayer	+380632576339	1666	2024-07-16	1144.69	out
1482	Bednar, King and Christiansen	+380090191140	1643	2024-02-25	7632.95	in
1483	Shanahan - Harvey	+380983681302	1772	2024-04-09	3508.55	out
1484	Cremin, Walsh and Okuneva	+380736506547	1947	2024-06-14	7421.78	out
1485	Terry, Murphy and Nicolas	+380288890856	1717	2024-01-12	8675.66	out
1486	Armstrong LLC	+380347838211	1762	2023-09-26	3198.67	out
1487	Abbott - Bayer	+380877754775	1563	2024-02-02	5470.62	in
1488	Dooley Inc	+380095332466	1602	2024-10-14	8455.69	out
1489	Dietrich, Cruickshank and D'Amore	+380713360851	1663	2024-05-20	5663.80	in
1490	Schimmel Inc	+380831205595	1993	2024-02-12	6733.46	out
1491	Walker - Krajcik	+380681783472	1896	2023-11-10	1596.74	out
1492	Ruecker - Yost	+380420675645	1920	2023-06-22	5381.02	out
1493	Glover Group 1	+380620137078	1634	2023-12-27	3272.96	out
1494	Volkman, Satterfield and Schuppe	+380311897200	1987	2022-12-20	1786.07	out
1495	Hamill - Rutherford	+380790565295	1639	2023-05-06	5047.38	out
1496	Quigley, McGlynn and Goyette	+380917192323	1932	2024-01-01	3126.74	out
1497	Ankunding - Smith	+380769363261	1833	2024-03-25	3628.59	out
1498	Collier Inc	+380645373089	1776	2022-11-03	2849.32	in
1499	Beatty LLC	+380911208118	1706	2024-03-05	8512.87	in
1500	Bednar - Kessler	+380413921408	1745	2024-06-16	3446.42	in
1501	Lesch LLC	+380785964449	1647	2023-03-06	1412.44	in
1502	Stiedemann LLC	+380021996020	1871	2023-11-30	2210.23	out
1503	Langosh - Stroman	+380543171787	1859	2024-06-12	6100.07	in
1504	Anderson LLC	+380831846112	1602	2023-09-17	5625.53	out
1505	Welch, Carroll and Quitzon	+380698554974	1701	2023-06-21	4467.28	out
1506	Bernhard, Moore and Satterfield	+380119468346	1525	2023-03-13	4285.48	out
1507	Heidenreich - Reilly	+380836331025	1646	2023-10-19	3014.11	out
1508	Jakubowski - Lockman	+380301148749	1723	2024-09-30	9724.91	in
1509	Bogisich and Sons	+380418906678	1737	2022-11-03	9660.65	out
1510	Collier, Little and Mayer	+380972702290	1584	2023-11-14	5305.17	in
1511	Quigley Group	+380814636468	1676	2024-05-02	7682.48	in
1512	Emmerich - Nader	+380415637735	1801	2023-10-31	8664.66	out
1513	Powlowski, Johns and Borer	+380786069308	1864	2023-07-11	3825.38	in
1514	Stokes, Crooks and Beier	+380724440694	1704	2024-07-04	4973.98	in
1515	Olson - Koss	+380125133113	1878	2024-07-03	3365.03	out
1516	Rodriguez LLC	+380249958301	1749	2023-01-10	3147.36	in
1517	Beer - Champlin	+380756196822	1554	2023-01-21	7327.50	in
1518	Heller - Fadel	+380836331025	1849	2024-01-12	9720.49	in
1519	Weimann - Beahan	+380087805165	1878	2023-07-26	2414.29	in
1520	Block, Wiegand and Trantow	+380881149099	1749	2023-02-28	9589.41	out
1521	Brown, Ernser and Harris	+380465085902	1608	2024-02-17	2301.68	out
1522	Dooley, Lakin and Rippin	+380981137697	1888	2023-01-22	9246.64	out
1523	Streich, O'Kon and Schowalter	+380636162557	1819	2024-09-15	6966.71	out
1524	Leannon Group 1	+380344145249	1628	2023-01-11	6131.70	out
1525	Stoltenberg, Rolfson and Kuphal	+380442026308	1968	2024-05-22	3814.67	out
1526	Marquardt Inc	+380989493604	1678	2023-01-13	2632.06	out
1527	Mante and Sons	+380642817268	1705	2022-10-31	7808.55	in
1528	Leannon Group 2	+380808401733	1959	2023-09-24	8060.62	in
1529	Volkman, Satterfield and Schuppe	+380134815529	1539	2024-03-30	4414.44	in
1530	Hintz - Sauer	+380702323272	1689	2024-01-21	5767.73	out
1531	Welch, Carroll and Quitzon	+380754829835	1670	2023-07-21	8173.39	out
1532	Kub, Bins and Schaden	+380265679989	1515	2024-07-13	4861.29	in
1533	Weber, Emmerich and Fay	+380222032641	1853	2024-06-12	1325.88	out
1534	Quitzon LLC	+380077849983	1535	2023-10-03	5747.04	out
1535	Cole and Sons	+380223567843	1605	2023-10-01	8909.28	in
1536	Kovacek LLC	+380232897722	1829	2023-03-29	5895.30	out
1537	Stracke Group	+380118355652	1811	2024-09-16	8812.88	in
1538	McCullough Inc	+380627282592	1868	2024-02-05	4486.65	in
1539	Walker - Krajcik	+380108384145	1649	2022-12-12	3973.24	in
1540	McClure - Rutherford	+380696387414	1995	2023-05-20	8116.54	out
1541	Willms - Wiegand	+380855723469	1641	2023-12-05	5801.81	in
1542	Ortiz - Stanton	+380064104924	1810	2023-09-10	6246.01	in
1543	Bosco - Grady	+380998865929	1525	2023-06-03	5453.39	out
1544	Bernhard, Moore and Satterfield	+380859936324	1818	2023-10-19	9228.01	out
1545	Lang Inc	+380821635966	1561	2024-05-17	6419.22	out
1546	Terry and Sons	+380220272315	1644	2023-03-07	9071.36	out
1547	Gottlieb Group	+380628039718	1770	2023-06-03	7331.74	in
1548	Stark, Bergnaum and Fisher	+380832932573	1938	2024-09-02	1660.55	out
1549	Blanda - Breitenberg	+380761748254	1790	2024-09-10	1222.96	in
1550	Terry, Murphy and Nicolas	+380585297393	1868	2024-02-12	8440.06	in
1551	Kohler, Oberbrunner and Reynolds	+380738063537	1936	2023-12-24	1504.47	out
1552	Hilll and Sons	+380061908449	1942	2022-12-16	7765.82	in
1553	Welch, Carroll and Quitzon	+380231111433	1671	2023-11-30	4344.40	in
1554	Huel, Schinner and O'Connell	+380625168742	1800	2023-10-08	1383.42	out
1555	Emmerich - Crist	+380023324280	1637	2023-01-18	4127.44	out
1556	Paucek - Bartoletti	+380328886266	1564	2024-05-15	7767.34	in
1557	Larkin - Bode	+380308085875	1642	2023-06-20	7779.19	out
1558	Toy LLC	+380249689055	1687	2023-01-28	7781.16	out
1559	Frami, Mante and Schaefer	+380413921408	1865	2024-07-30	2544.63	in
1560	Stark, Bergnaum and Fisher	+380737537839	1949	2022-12-08	7964.56	in
1561	Lakin LLC	+380127811113	1858	2024-02-01	9283.68	out
1562	Leannon - Koch	+380439461471	1946	2022-11-17	7713.10	out
1563	Cole and Sons	+380611830453	1530	2023-11-04	7913.32	in
1564	Torp - Kunde	+380593164897	1517	2023-02-04	2191.00	in
1565	Leannon - Koch	+380616265071	1546	2023-10-02	5047.14	out
1566	Welch, Carroll and Quitzon	+380123024644	1939	2024-03-23	6240.73	in
1567	VonRueden Inc	+380578781267	1877	2023-12-29	3515.40	out
1568	Bauch - Cummerata	+380716098940	1559	2023-08-23	4488.82	in
1569	Walker - Waters	+380421549515	1626	2024-08-11	1628.06	out
1570	Sanford and Sons	+380752112117	1730	2024-03-07	2032.10	in
1571	Hammes Group	+380474972934	1521	2023-11-29	6212.74	in
1572	Haley Inc	+380849254990	1667	2023-12-05	2272.02	out
1573	Murazik LLC	+380160703104	1799	2023-06-02	6859.65	in
1574	Goyette, Sauer and Wolff	+380869534011	1787	2023-09-03	7343.36	out
1575	Kunde - Hodkiewicz	+380437838309	1741	2023-01-09	9567.88	out
1576	Champlin - Veum	+380831580992	1695	2022-12-22	7532.07	in
1577	Wolf, Goldner and Kihn	+380711641864	1767	2023-06-19	2179.47	out
1578	Trantow - Nikolaus	+380344740233	1890	2024-01-06	1398.14	out
1579	Balistreri Inc	+380996838491	1932	2023-05-12	4774.39	in
1580	Cole Group	+380358236687	1835	2024-08-24	9895.82	out
1581	Luettgen Inc	+380234033341	1503	2024-01-24	4692.13	in
1582	Rogahn - Wiza	+380159553650	1868	2024-04-15	2878.12	in
1583	Beatty LLC	+380591177571	1857	2023-06-30	2024.88	in
1584	Botsford - Cronin	+380498244983	1532	2024-02-05	7058.74	in
1585	Reichert and Sons	+380388928271	1629	2023-06-13	8619.70	in
1586	Bogisich and Sons	+380617989751	1718	2024-10-24	3896.99	out
1587	Leannon Group	+380348008062	1574	2023-08-18	3042.76	in
1588	Treutel Group	+380055746349	1789	2023-05-27	7761.66	in
1589	Feil, Windler and Parker	+380542614825	1681	2023-01-30	8330.51	out
1590	Kemmer, Reinger and Kirlin	+380455275510	1650	2024-06-11	8957.44	in
1591	West, Sipes and Kuhn	+380574606149	1667	2023-03-24	7992.57	in
1592	Abshire and Sons	+380317099925	1844	2023-01-22	5862.84	out
1593	Spinka and Sons	+380662558582	1884	2023-03-13	1927.47	in
1594	Hessel, Legros and West	+380162253458	1982	2023-08-27	3319.77	in
1595	Grant, Abshire and Rowe	+380026831767	1708	2023-02-01	2012.07	out
1596	Halvorson - Hand	+380676571377	1924	2024-08-28	2303.90	in
1597	Windler Inc	+380847906776	1521	2023-04-25	9238.32	out
1598	Powlowski, Walter and Rath	+380405242601	1671	2023-03-28	2248.13	out
1599	Lakin LLC	+380993054133	1704	2023-08-15	1570.76	in
1600	Bartoletti Inc	+380209429553	1556	2023-07-31	4707.60	in
1601	Ortiz - Oberbrunner	+380738541167	1959	2023-11-22	1981.87	in
1602	Bins - Littel	+380786069308	1695	2024-02-02	2098.25	in
1603	Treutel - Streich	+380263837665	1512	2024-07-25	6619.57	in
1604	Lueilwitz Group	+380435431603	1582	2024-05-04	8850.11	in
1605	McDermott - Lubowitz	+380905856732	1764	2023-07-12	4865.38	out
1606	Windler, Connelly and Wintheiser	+380739819586	1560	2022-11-27	6198.58	in
1607	Braun - Bechtelar	+380355827503	1597	2023-06-07	3805.99	out
1608	Yost, Cole and Kautzer	+380357242961	1590	2024-04-22	2592.15	in
1609	Ritchie and Sons	+380875852083	1582	2023-08-20	8927.57	out
1619	Abbott - Bayer	+380001409943	1502	2024-11-06	3000.00	out
1620	Ankunding - Smith	+380006100448	1600	2024-11-06	2500.00	out
1628	Abbott LLC	+380618609992	1521	2024-10-01	10000.00	out
1629	Abshire and Sons	+380860052833	1748	2024-10-02	5000.00	out
1630	Abbott - Bayer	+380001409943	1502	2024-11-18	3100.00	in
1631	Abbott - Bayer	+380001409943	1502	2024-11-19	1000.00	in
1632	Abbott - Bayer	+380001409943	1502	2024-11-19	1000.00	in
1633	Abbott - Bayer	+380001409943	1502	2024-11-19	1000.00	in
1621	Bailey Group	\N	2000	2024-11-06	1800.00	out
1255	Mohr Group	\N	1902	2024-10-04	7707.98	out
1392	Hauck, Lakin and Nicolas	\N	1856	2023-03-16	6770.24	in
\.


--
-- TOC entry 4949 (class 0 OID 16562)
-- Dependencies: 224
-- Data for Name: list_entry; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.list_entry (invoice_id, product_name, count, price) FROM stdin;
1296	Awesome Cotton Gloves	65.46	249.16
1345	Awesome Cotton Gloves	37.38	74.26
1354	Awesome Cotton Gloves	8.25	492.14
1385	Awesome Cotton Gloves	19.28	563.18
1453	Awesome Cotton Gloves	12.30	922.15
1507	Awesome Cotton Gloves	67.25	196.18
1516	Awesome Cotton Gloves	59.77	854.91
1544	Awesome Cotton Gloves	70.69	33.92
1546	Awesome Cotton Gloves	9.36	402.53
1560	Awesome Cotton Gloves	91.55	431.12
1574	Awesome Cotton Gloves	47.82	121.88
1591	Awesome Cotton Gloves	40.25	905.34
1239	Awesome Cotton Sausages	26.15	594.56
1284	Awesome Cotton Sausages	34.44	434.51
1369	Awesome Cotton Sausages	63.29	778.63
1487	Awesome Cotton Sausages	3.57	600.48
1488	Awesome Cotton Sausages	26.36	532.64
1530	Awesome Cotton Sausages	28.42	232.48
1548	Awesome Cotton Sausages	43.94	285.22
1226	Awesome Fresh Chicken	7.68	212.32
1256	Awesome Fresh Chicken	87.75	341.70
1318	Awesome Fresh Chicken	91.16	957.93
1362	Awesome Fresh Chicken	38.24	421.68
1383	Awesome Fresh Chicken	27.70	567.90
1417	Awesome Fresh Chicken	48.59	558.96
1479	Awesome Fresh Chicken	70.70	972.04
1564	Awesome Fresh Chicken	94.46	758.06
1591	Awesome Fresh Chicken	35.45	627.82
1236	Awesome Fresh Chips	89.46	565.33
1252	Awesome Fresh Chips	56.13	597.24
1273	Awesome Fresh Chips	23.37	561.68
1280	Awesome Fresh Chips	51.29	549.06
1299	Awesome Fresh Chips	63.30	412.88
1321	Awesome Fresh Chips	99.21	447.71
1345	Awesome Fresh Chips	74.89	856.36
1408	Awesome Fresh Chips	23.37	780.10
1417	Awesome Fresh Chips	99.32	130.49
1454	Awesome Fresh Chips	98.20	12.28
1498	Awesome Fresh Chips	71.24	68.21
1509	Awesome Fresh Chips	54.26	743.35
1531	Awesome Fresh Chips	95.27	151.85
1554	Awesome Fresh Chips	93.60	984.59
1563	Awesome Fresh Chips	92.10	676.74
1567	Awesome Fresh Chips	69.93	965.86
1584	Awesome Fresh Chips	42.23	396.93
1251	Awesome Metal Hat	21.08	171.16
1317	Awesome Metal Hat	29.58	705.53
1334	Awesome Metal Hat	54.89	235.82
1372	Awesome Metal Hat	17.76	50.11
1380	Awesome Metal Hat	81.33	903.67
1407	Awesome Metal Hat	49.12	827.00
1448	Awesome Metal Hat	4.86	353.62
1453	Awesome Metal Hat	6.81	802.64
1498	Awesome Metal Hat	49.17	499.86
1514	Awesome Metal Hat	19.58	111.70
1516	Awesome Metal Hat	6.19	408.98
1517	Awesome Metal Hat	84.58	651.65
1539	Awesome Metal Hat	23.39	429.73
1597	Awesome Metal Hat	6.82	350.38
1229	Awesome Metal Shoes	19.78	116.32
1265	Awesome Metal Shoes	79.18	942.90
1269	Awesome Metal Shoes	69.51	604.16
1354	Awesome Metal Shoes	69.01	473.65
1385	Awesome Metal Shoes	31.36	515.30
1400	Awesome Metal Shoes	19.69	496.56
1418	Awesome Metal Shoes	27.51	475.44
1500	Awesome Metal Shoes	99.96	980.75
1516	Awesome Metal Shoes	87.91	890.13
1583	Awesome Metal Shoes	38.51	72.58
1213	Awesome Plastic Tuna	55.26	259.91
1271	Awesome Plastic Tuna	2.27	181.29
1273	Awesome Plastic Tuna	48.06	720.02
1294	Awesome Plastic Tuna	72.40	571.74
1299	Awesome Plastic Tuna	73.65	544.73
1302	Awesome Plastic Tuna	20.95	273.18
1333	Awesome Plastic Tuna	20.20	397.57
1335	Awesome Plastic Tuna	58.53	390.11
1366	Awesome Plastic Tuna	90.36	533.97
1404	Awesome Plastic Tuna	17.07	294.38
1438	Awesome Plastic Tuna	1.45	807.39
1467	Awesome Plastic Tuna	86.29	571.01
1469	Awesome Plastic Tuna	51.04	958.73
1493	Awesome Plastic Tuna	69.12	794.27
1506	Awesome Plastic Tuna	44.27	629.81
1570	Awesome Plastic Tuna	98.21	879.97
1576	Awesome Plastic Tuna	1.95	187.50
1214	Awesome Rubber Soap	23.52	181.73
1217	Awesome Rubber Soap	71.91	308.87
1290	Awesome Rubber Soap	4.73	263.68
1293	Awesome Rubber Soap	20.55	833.48
1295	Awesome Rubber Soap	3.75	106.02
1305	Awesome Rubber Soap	34.27	945.23
1334	Awesome Rubber Soap	9.85	89.45
1341	Awesome Rubber Soap	97.59	641.40
1363	Awesome Rubber Soap	87.98	855.83
1378	Awesome Rubber Soap	56.89	510.63
1401	Awesome Rubber Soap	30.38	779.64
1406	Awesome Rubber Soap	55.21	312.91
1465	Awesome Rubber Soap	32.37	285.94
1484	Awesome Rubber Soap	88.12	62.80
1529	Awesome Rubber Soap	44.28	134.56
1542	Awesome Rubber Soap	92.92	151.47
1324	Ergonomic Fresh Mouse	29.93	77.28
1362	Ergonomic Fresh Mouse	69.50	186.29
1365	Ergonomic Fresh Mouse	65.98	365.04
1428	Ergonomic Fresh Mouse	1.02	453.14
1447	Ergonomic Fresh Mouse	42.80	958.12
1462	Ergonomic Fresh Mouse	31.19	737.37
1522	Ergonomic Fresh Mouse	45.98	279.95
1548	Ergonomic Fresh Mouse	48.14	304.60
1581	Ergonomic Fresh Mouse	57.89	534.91
1591	Ergonomic Fresh Mouse	27.26	704.11
1223	Ergonomic Frozen Chips	56.00	224.03
1270	Ergonomic Frozen Chips	74.82	681.66
1327	Ergonomic Frozen Chips	56.03	215.25
1361	Ergonomic Frozen Chips	24.30	140.09
1410	Ergonomic Frozen Chips	95.69	266.29
1441	Ergonomic Frozen Chips	27.86	262.95
1457	Ergonomic Frozen Chips	17.17	891.24
1510	Ergonomic Frozen Chips	28.97	711.42
1532	Ergonomic Frozen Chips	5.05	165.95
1577	Ergonomic Frozen Chips	15.85	103.07
1593	Ergonomic Frozen Chips	91.49	751.48
1225	Ergonomic Granite Cheese	75.66	749.82
1232	Ergonomic Granite Cheese	18.53	882.47
1271	Ergonomic Granite Cheese	8.30	319.09
1335	Ergonomic Granite Cheese	57.53	510.46
1353	Ergonomic Granite Cheese	49.61	424.24
1356	Ergonomic Granite Cheese	3.14	162.67
1377	Ergonomic Granite Cheese	34.80	566.49
1401	Ergonomic Granite Cheese	86.50	127.10
1454	Ergonomic Granite Cheese	3.73	395.07
1531	Ergonomic Granite Cheese	36.59	892.91
1536	Ergonomic Granite Cheese	24.30	285.53
1583	Ergonomic Granite Cheese	95.02	487.70
1237	Ergonomic Metal Cheese	83.06	234.46
1273	Ergonomic Metal Cheese	31.35	293.09
1315	Ergonomic Metal Cheese	89.01	196.98
1341	Ergonomic Metal Cheese	55.10	994.49
1356	Ergonomic Metal Cheese	8.08	604.91
1359	Ergonomic Metal Cheese	29.60	136.44
1446	Ergonomic Metal Cheese	28.17	918.79
1450	Ergonomic Metal Cheese	71.48	948.95
1487	Ergonomic Metal Cheese	90.65	287.83
1543	Ergonomic Metal Cheese	38.02	692.44
1552	Ergonomic Metal Cheese	28.24	735.57
1221	Ergonomic Plastic Gloves	66.94	635.13
1298	Ergonomic Plastic Gloves	35.63	64.97
1327	Ergonomic Plastic Gloves	42.42	402.09
1349	Ergonomic Plastic Gloves	8.08	187.72
1418	Ergonomic Plastic Gloves	56.77	147.18
1476	Ergonomic Plastic Gloves	60.02	760.31
1495	Ergonomic Plastic Gloves	52.88	713.67
1514	Ergonomic Plastic Gloves	67.16	176.33
1233	Ergonomic Rubber Sausages	60.27	148.97
1283	Ergonomic Rubber Sausages	7.64	268.34
1348	Ergonomic Rubber Sausages	30.88	501.75
1502	Ergonomic Rubber Sausages	82.35	202.32
1518	Ergonomic Rubber Sausages	66.76	549.70
1520	Ergonomic Rubber Sausages	86.82	539.11
1542	Ergonomic Rubber Sausages	12.79	617.15
1578	Ergonomic Rubber Sausages	43.66	46.38
1213	Ergonomic Soft Bacon	18.77	199.98
1231	Ergonomic Soft Bacon	7.84	654.76
1274	Ergonomic Soft Bacon	51.74	265.03
1281	Ergonomic Soft Bacon	3.78	497.16
1314	Ergonomic Soft Bacon	17.05	255.94
1463	Ergonomic Soft Bacon	6.69	870.26
1568	Ergonomic Soft Bacon	75.74	741.81
1250	Ergonomic Steel Bike	39.27	399.38
1307	Ergonomic Steel Bike	7.14	559.03
1318	Ergonomic Steel Bike	5.62	879.22
1323	Ergonomic Steel Bike	66.52	626.57
1361	Ergonomic Steel Bike	73.10	994.01
1496	Ergonomic Steel Bike	53.35	682.67
1509	Ergonomic Steel Bike	23.12	710.73
1544	Ergonomic Steel Bike	1.56	233.94
1588	Ergonomic Steel Bike	12.59	103.16
1595	Ergonomic Steel Bike	7.30	181.98
1240	Ergonomic Wooden Table	46.28	683.89
1283	Ergonomic Wooden Table	36.60	496.28
1298	Ergonomic Wooden Table	46.92	209.44
1412	Ergonomic Wooden Table	91.33	562.29
1501	Ergonomic Wooden Table	58.13	535.47
1599	Ergonomic Wooden Table	8.47	348.03
1255	Fantastic Concrete Fish	70.51	153.99
1267	Fantastic Concrete Fish	92.00	177.50
1304	Fantastic Concrete Fish	9.13	102.88
1333	Fantastic Concrete Fish	48.27	677.19
1348	Fantastic Concrete Fish	92.68	236.56
1369	Fantastic Concrete Fish	11.88	641.91
1379	Fantastic Concrete Fish	43.22	412.67
1425	Fantastic Concrete Fish	83.44	81.45
1460	Fantastic Concrete Fish	25.33	204.80
1529	Fantastic Concrete Fish	59.99	363.72
1553	Fantastic Concrete Fish	10.90	80.83
1559	Fantastic Concrete Fish	88.47	880.77
1586	Fantastic Concrete Fish	96.23	217.72
1588	Fantastic Concrete Fish	40.92	612.46
1251	Fantastic Fresh Chips	96.35	233.72
1262	Fantastic Fresh Chips	16.74	332.86
1283	Fantastic Fresh Chips	17.19	663.17
1294	Fantastic Fresh Chips	57.16	614.41
1333	Fantastic Fresh Chips	39.33	307.72
1411	Fantastic Fresh Chips	55.23	558.67
1425	Fantastic Fresh Chips	74.02	231.71
1576	Fantastic Fresh Chips	17.20	888.05
1609	Fantastic Fresh Chips	89.70	173.35
1230	Fantastic Fresh Salad	22.53	694.98
1256	Fantastic Fresh Salad	69.77	624.84
1276	Fantastic Fresh Salad	39.21	437.07
1287	Fantastic Fresh Salad	97.21	416.77
1298	Fantastic Fresh Salad	81.72	756.07
1382	Fantastic Fresh Salad	73.46	531.65
1394	Fantastic Fresh Salad	73.62	923.96
1421	Fantastic Fresh Salad	59.97	433.63
1431	Fantastic Fresh Salad	24.92	303.28
1476	Fantastic Fresh Salad	88.87	488.00
1525	Fantastic Fresh Salad	35.47	54.53
1577	Fantastic Fresh Salad	19.58	802.19
1604	Fantastic Fresh Salad	45.84	560.26
1609	Fantastic Fresh Salad	42.75	546.00
1255	Fantastic Frozen Chicken	96.57	860.89
1294	Fantastic Frozen Chicken	41.09	317.15
1312	Fantastic Frozen Chicken	25.30	839.62
1354	Fantastic Frozen Chicken	62.14	356.70
1378	Fantastic Frozen Chicken	31.14	798.84
1445	Fantastic Frozen Chicken	95.11	896.24
1451	Fantastic Frozen Chicken	28.02	485.50
1485	Fantastic Frozen Chicken	54.04	376.79
1489	Fantastic Frozen Chicken	94.07	355.06
1565	Fantastic Frozen Chicken	38.87	844.02
1216	Fantastic Granite Chips	3.39	232.99
1224	Fantastic Granite Chips	75.99	671.43
1244	Fantastic Granite Chips	98.88	36.59
1251	Fantastic Granite Chips	16.32	21.37
1320	Fantastic Granite Chips	84.32	722.53
1400	Fantastic Granite Chips	48.44	839.54
1401	Fantastic Granite Chips	40.31	98.45
1433	Fantastic Granite Chips	29.32	642.04
1476	Fantastic Granite Chips	53.57	926.30
1479	Fantastic Granite Chips	34.15	755.55
1496	Fantastic Granite Chips	58.24	144.00
1497	Fantastic Granite Chips	26.99	248.56
1408	Fantastic Granite Pizza	85.50	748.25
1470	Fantastic Granite Pizza	88.35	359.87
1507	Fantastic Granite Pizza	21.71	323.39
1523	Fantastic Granite Pizza	85.95	473.18
1531	Fantastic Granite Pizza	77.28	31.15
1545	Fantastic Granite Pizza	48.34	947.62
1557	Fantastic Granite Pizza	62.49	488.36
1244	Fantastic Granite Tuna	18.74	759.19
1279	Fantastic Granite Tuna	21.13	485.81
1288	Fantastic Granite Tuna	19.29	455.91
1321	Fantastic Granite Tuna	57.34	891.54
1400	Fantastic Granite Tuna	18.99	659.23
1423	Fantastic Granite Tuna	22.83	115.98
1470	Fantastic Granite Tuna	21.82	520.89
1585	Fantastic Granite Tuna	46.22	955.43
1231	Fantastic Rubber Keyboard	67.45	625.23
1236	Fantastic Rubber Keyboard	38.19	257.41
1366	Fantastic Rubber Keyboard	67.65	206.49
1391	Fantastic Rubber Keyboard	84.97	487.33
1401	Fantastic Rubber Keyboard	94.54	63.25
1441	Fantastic Rubber Keyboard	48.54	56.05
1491	Fantastic Rubber Keyboard	23.68	379.83
1554	Fantastic Rubber Keyboard	71.88	712.20
1215	Fantastic Soft Bike	1.90	781.32
1322	Fantastic Soft Bike	68.76	837.50
1354	Fantastic Soft Bike	7.97	269.81
1360	Fantastic Soft Bike	95.74	496.87
1407	Fantastic Soft Bike	58.89	46.26
1430	Fantastic Soft Bike	9.84	428.99
1436	Fantastic Soft Bike	96.26	975.24
1442	Fantastic Soft Bike	68.75	762.20
1480	Fantastic Soft Bike	31.23	336.53
1482	Fantastic Soft Bike	31.85	825.67
1510	Fantastic Soft Bike	13.57	816.40
1237	Fantastic Steel Chicken	99.54	286.75
1294	Fantastic Steel Chicken	44.88	911.25
1330	Fantastic Steel Chicken	48.47	722.24
1356	Fantastic Steel Chicken	93.31	56.24
1421	Fantastic Steel Chicken	39.47	948.31
1536	Fantastic Steel Chicken	14.43	563.25
1589	Fantastic Steel Chicken	21.76	510.24
1225	Generic Concrete Shirt	36.63	977.00
1239	Generic Concrete Shirt	52.33	935.06
1315	Generic Concrete Shirt	44.14	78.20
1358	Generic Concrete Shirt	72.17	791.46
1373	Generic Concrete Shirt	66.56	905.56
1420	Generic Concrete Shirt	48.62	814.78
1448	Generic Concrete Shirt	59.04	365.24
1457	Generic Concrete Shirt	69.18	16.85
1501	Generic Concrete Shirt	35.90	564.51
1531	Generic Concrete Shirt	35.07	779.58
1587	Generic Concrete Shirt	76.27	301.54
1220	Generic Fresh Car	79.58	651.12
1224	Generic Fresh Car	97.03	777.16
1258	Generic Fresh Car	11.46	952.49
1259	Generic Fresh Car	66.15	703.26
1271	Generic Fresh Car	95.03	628.57
1288	Generic Fresh Car	94.61	775.22
1319	Generic Fresh Car	75.14	15.55
1330	Generic Fresh Car	3.62	102.25
1360	Generic Fresh Car	56.35	250.37
1386	Generic Fresh Car	61.12	516.96
1412	Generic Fresh Car	73.92	238.58
1419	Generic Fresh Car	41.70	693.50
1445	Generic Fresh Car	23.82	731.88
1506	Generic Fresh Car	70.31	944.29
1229	Generic Fresh Chair	13.71	361.20
1238	Generic Fresh Chair	68.59	755.75
1254	Generic Fresh Chair	60.17	115.94
1340	Generic Fresh Chair	81.11	127.85
1364	Generic Fresh Chair	57.49	555.66
1377	Generic Fresh Chair	56.44	771.74
1420	Generic Fresh Chair	41.89	37.26
1475	Generic Fresh Chair	56.45	348.27
1478	Generic Fresh Chair	20.12	681.67
1497	Generic Fresh Chair	27.93	806.03
1501	Generic Fresh Chair	97.73	132.78
1593	Generic Fresh Chair	41.56	674.91
1238	Generic Fresh Keyboard	50.53	284.92
1304	Generic Fresh Keyboard	52.03	240.00
1332	Generic Fresh Keyboard	32.67	33.47
1384	Generic Fresh Keyboard	6.09	813.45
1408	Generic Fresh Keyboard	22.79	359.07
1428	Generic Fresh Keyboard	47.78	186.95
1466	Generic Fresh Keyboard	42.66	850.09
1520	Generic Fresh Keyboard	19.00	828.30
1537	Generic Fresh Keyboard	69.01	559.01
1551	Generic Fresh Keyboard	30.95	811.15
1276	Generic Granite Bacon	25.57	852.65
1296	Generic Granite Bacon	87.99	693.35
1340	Generic Granite Bacon	45.50	165.60
1378	Generic Granite Bacon	21.34	375.60
1390	Generic Granite Bacon	56.56	975.91
1403	Generic Granite Bacon	20.37	248.60
1467	Generic Granite Bacon	96.27	753.92
1470	Generic Granite Bacon	46.12	992.80
1550	Generic Granite Bacon	50.34	880.42
1580	Generic Granite Bacon	78.82	106.13
1312	Generic Plastic Chair	1.66	571.72
1316	Generic Plastic Chair	74.98	184.27
1382	Generic Plastic Chair	44.26	361.67
1463	Generic Plastic Chair	28.56	423.35
1479	Generic Plastic Chair	95.27	397.18
1506	Generic Plastic Chair	91.69	629.67
1561	Generic Plastic Chair	92.69	301.49
1564	Generic Plastic Chair	93.95	397.08
1590	Generic Plastic Chair	59.15	271.66
1591	Generic Plastic Chair	62.38	722.28
1214	Generic Rubber Keyboard	99.89	931.69
1254	Generic Rubber Keyboard	18.47	795.92
1316	Generic Rubber Keyboard	9.79	807.17
1333	Generic Rubber Keyboard	90.21	629.86
1360	Generic Rubber Keyboard	28.08	296.16
1378	Generic Rubber Keyboard	37.32	874.75
1413	Generic Rubber Keyboard	76.00	202.45
1509	Generic Rubber Keyboard	19.89	610.89
1510	Generic Rubber Keyboard	96.85	258.37
1548	Generic Rubber Keyboard	22.06	411.85
1565	Generic Rubber Keyboard	52.67	922.86
1581	Generic Rubber Keyboard	26.33	741.08
1220	Generic Rubber Salad	51.45	115.89
1276	Generic Rubber Salad	53.89	618.10
1325	Generic Rubber Salad	84.96	732.69
1392	Generic Rubber Salad	73.54	499.94
1429	Generic Rubber Salad	79.64	53.22
1541	Generic Rubber Salad	33.55	375.00
1216	Generic Rubber Soap	33.53	37.14
1231	Generic Rubber Soap	35.62	798.96
1254	Generic Rubber Soap	24.43	948.99
1259	Generic Rubber Soap	29.42	581.79
1261	Generic Rubber Soap	64.57	741.40
1287	Generic Rubber Soap	3.96	33.96
1302	Generic Rubber Soap	36.35	477.80
1333	Generic Rubber Soap	52.51	935.54
1430	Generic Rubber Soap	12.65	373.59
1437	Generic Rubber Soap	39.75	383.08
1457	Generic Rubber Soap	27.16	512.49
1533	Generic Rubber Soap	1.89	718.93
1587	Generic Rubber Soap	30.90	747.32
1249	Generic Soft Bike	83.23	294.31
1254	Generic Soft Bike	46.35	914.64
1257	Generic Soft Bike	32.40	708.60
1287	Generic Soft Bike	85.68	163.50
1307	Generic Soft Bike	74.18	22.04
1336	Generic Soft Bike	95.87	243.08
1343	Generic Soft Bike	29.17	426.34
1358	Generic Soft Bike	67.95	716.97
1402	Generic Soft Bike	65.32	518.87
1434	Generic Soft Bike	65.50	379.27
1450	Generic Soft Bike	76.20	402.11
1520	Generic Soft Bike	52.32	948.83
1524	Generic Soft Bike	23.62	607.91
1540	Generic Soft Bike	49.46	512.35
1592	Generic Soft Bike	4.48	752.49
1249	Generic Soft Salad	80.99	974.39
1301	Generic Soft Salad	44.76	190.17
1419	Generic Soft Salad	77.94	405.51
1450	Generic Soft Salad	45.13	734.31
1528	Generic Soft Salad	84.85	235.35
1530	Generic Soft Salad	22.60	779.20
1608	Generic Soft Salad	3.82	98.38
1217	Generic Steel Keyboard	8.86	565.67
1243	Generic Steel Keyboard	95.30	838.23
1304	Generic Steel Keyboard	36.93	301.91
1350	Generic Steel Keyboard	68.90	476.60
1368	Generic Steel Keyboard	70.00	49.02
1384	Generic Steel Keyboard	90.20	322.55
1406	Generic Steel Keyboard	14.15	386.82
1471	Generic Steel Keyboard	64.66	755.78
1489	Generic Steel Keyboard	53.13	380.69
1503	Generic Steel Keyboard	8.03	263.83
1518	Generic Steel Keyboard	31.25	916.40
1574	Generic Steel Keyboard	56.38	669.17
1589	Generic Steel Keyboard	77.05	785.47
1265	Generic Wooden Gloves	51.60	688.47
1305	Generic Wooden Gloves	84.03	633.99
1350	Generic Wooden Gloves	16.64	400.66
1358	Generic Wooden Gloves	7.04	87.55
1379	Generic Wooden Gloves	57.55	921.82
1441	Generic Wooden Gloves	85.62	259.81
1506	Generic Wooden Gloves	97.92	368.20
1539	Generic Wooden Gloves	46.75	407.80
1251	Generic Wooden Towels	12.11	169.05
1278	Generic Wooden Towels	16.00	908.86
1286	Generic Wooden Towels	12.01	114.28
1304	Generic Wooden Towels	96.91	508.71
1306	Generic Wooden Towels	72.39	926.71
1384	Generic Wooden Towels	6.38	794.53
1427	Generic Wooden Towels	30.91	898.56
1502	Generic Wooden Towels	50.16	492.48
1529	Generic Wooden Towels	90.79	244.20
1547	Generic Wooden Towels	60.75	813.10
1552	Generic Wooden Towels	12.09	49.38
1218	Gorgeous Fresh Chicken	6.27	763.44
1321	Gorgeous Fresh Chicken	3.80	870.61
1383	Gorgeous Fresh Chicken	80.10	320.27
1422	Gorgeous Fresh Chicken	31.24	61.10
1517	Gorgeous Fresh Chicken	3.31	798.31
1531	Gorgeous Fresh Chicken	14.03	774.08
1533	Gorgeous Fresh Chicken	61.61	678.43
1572	Gorgeous Fresh Chicken	19.42	687.42
1595	Gorgeous Fresh Chicken	16.94	48.93
1278	Gorgeous Fresh Fish	51.75	844.55
1298	Gorgeous Fresh Fish	46.30	31.06
1438	Gorgeous Fresh Fish	30.89	250.78
1459	Gorgeous Fresh Fish	37.35	390.69
1464	Gorgeous Fresh Fish	51.63	107.55
1542	Gorgeous Fresh Fish	45.26	228.67
1553	Gorgeous Fresh Fish	34.83	533.51
1567	Gorgeous Fresh Fish	79.04	611.87
1591	Gorgeous Fresh Fish	4.13	798.02
1385	Gorgeous Rubber Computer	76.34	20.63
1456	Gorgeous Rubber Computer	1.12	984.93
1470	Gorgeous Rubber Computer	17.52	201.59
1521	Gorgeous Rubber Computer	32.25	91.93
1524	Gorgeous Rubber Computer	18.26	901.58
1235	Gorgeous Soft Car	28.19	210.11
1254	Gorgeous Soft Car	23.74	137.67
1315	Gorgeous Soft Car	41.61	911.26
1316	Gorgeous Soft Car	1.00	750.60
1364	Gorgeous Soft Car	82.40	273.68
1487	Gorgeous Soft Car	41.40	945.28
1257	Gorgeous Soft Cheese	82.98	830.45
1325	Gorgeous Soft Cheese	14.95	776.06
1366	Gorgeous Soft Cheese	57.10	871.39
1406	Gorgeous Soft Cheese	21.37	817.94
1500	Gorgeous Soft Cheese	73.17	995.16
1501	Gorgeous Soft Cheese	12.89	26.14
1531	Gorgeous Soft Cheese	45.02	457.19
1556	Gorgeous Soft Cheese	36.45	941.07
1235	Gorgeous Soft Chicken	79.23	216.88
1299	Gorgeous Soft Chicken	24.12	386.11
1317	Gorgeous Soft Chicken	74.86	279.23
1320	Gorgeous Soft Chicken	40.15	685.27
1349	Gorgeous Soft Chicken	5.94	215.52
1442	Gorgeous Soft Chicken	98.74	855.04
1507	Gorgeous Soft Chicken	26.51	497.99
1605	Gorgeous Soft Chicken	61.82	377.93
1241	Gorgeous Soft Pants	39.84	204.48
1244	Gorgeous Soft Pants	20.06	498.36
1309	Gorgeous Soft Pants	3.32	514.29
1423	Gorgeous Soft Pants	84.67	161.28
1431	Gorgeous Soft Pants	38.53	964.00
1452	Gorgeous Soft Pants	77.55	987.17
1580	Gorgeous Soft Pants	13.92	950.31
1221	Gorgeous Soft Sausages	33.57	775.80
1458	Gorgeous Soft Sausages	66.81	107.46
1474	Gorgeous Soft Sausages	87.37	968.80
1512	Gorgeous Soft Sausages	35.33	49.97
1533	Gorgeous Soft Sausages	6.73	808.07
1562	Gorgeous Soft Sausages	86.89	801.17
1566	Gorgeous Soft Sausages	63.66	165.36
1604	Gorgeous Soft Sausages	26.16	879.41
1244	Gorgeous Soft Shoes	48.03	227.97
1300	Gorgeous Soft Shoes	9.26	848.49
1312	Gorgeous Soft Shoes	66.28	848.51
1317	Gorgeous Soft Shoes	51.49	355.52
1338	Gorgeous Soft Shoes	87.12	104.40
1345	Gorgeous Soft Shoes	7.36	227.30
1397	Gorgeous Soft Shoes	51.90	608.06
1440	Gorgeous Soft Shoes	88.14	942.81
1447	Gorgeous Soft Shoes	44.38	294.07
1534	Gorgeous Soft Shoes	47.92	25.81
1583	Gorgeous Soft Shoes	45.77	757.61
1225	Gorgeous Soft Towels	45.64	785.65
1349	Gorgeous Soft Towels	33.94	915.18
1447	Gorgeous Soft Towels	59.65	44.22
1512	Gorgeous Soft Towels	73.60	988.27
1518	Gorgeous Soft Towels	5.95	433.79
1531	Gorgeous Soft Towels	42.83	679.97
1573	Gorgeous Soft Towels	32.62	324.30
1232	Gorgeous Steel Computer	14.44	285.41
1239	Gorgeous Steel Computer	14.56	812.63
1305	Gorgeous Steel Computer	85.45	69.57
1408	Gorgeous Steel Computer	34.90	872.44
1578	Gorgeous Steel Computer	32.73	639.27
1596	Gorgeous Steel Computer	97.93	187.92
1231	Gorgeous Wooden Bike	66.56	372.28
1279	Gorgeous Wooden Bike	59.69	898.07
1286	Gorgeous Wooden Bike	41.18	136.41
1300	Gorgeous Wooden Bike	43.86	148.28
1334	Gorgeous Wooden Bike	17.80	261.09
1369	Gorgeous Wooden Bike	79.58	35.74
1395	Gorgeous Wooden Bike	54.16	11.32
1424	Gorgeous Wooden Bike	74.46	148.80
1487	Gorgeous Wooden Bike	22.85	683.54
1508	Gorgeous Wooden Bike	46.78	892.97
1514	Gorgeous Wooden Bike	16.95	710.41
1592	Gorgeous Wooden Bike	85.91	631.25
1212	Gorgeous Wooden Chicken	3.12	263.10
1221	Gorgeous Wooden Chicken	63.51	141.02
1253	Gorgeous Wooden Chicken	99.30	446.84
1317	Gorgeous Wooden Chicken	95.64	757.54
1342	Gorgeous Wooden Chicken	33.79	407.64
1361	Gorgeous Wooden Chicken	46.01	694.97
1369	Gorgeous Wooden Chicken	86.74	278.30
1405	Gorgeous Wooden Chicken	14.39	84.77
1464	Gorgeous Wooden Chicken	90.40	21.94
1524	Gorgeous Wooden Chicken	72.97	91.06
1537	Gorgeous Wooden Chicken	52.96	737.29
1566	Gorgeous Wooden Chicken	37.12	834.41
1568	Gorgeous Wooden Chicken	67.65	690.59
1585	Gorgeous Wooden Chicken	9.54	922.50
1594	Gorgeous Wooden Chicken	79.39	628.54
1218	Handcrafted Concrete Fish	63.98	356.98
1289	Handcrafted Concrete Fish	27.45	735.64
1333	Handcrafted Concrete Fish	30.40	402.37
1420	Handcrafted Concrete Fish	9.69	294.41
1235	Practical Metal Hat	96.81	976.40
1429	Handcrafted Concrete Fish	74.75	558.42
1471	Handcrafted Concrete Fish	56.47	52.30
1474	Handcrafted Concrete Fish	12.76	566.21
1477	Handcrafted Concrete Fish	67.43	619.17
1561	Handcrafted Concrete Fish	26.83	914.59
1575	Handcrafted Concrete Fish	41.75	620.07
1231	Handcrafted Concrete Pizza	49.50	208.56
1249	Handcrafted Concrete Pizza	25.75	731.69
1254	Handcrafted Concrete Pizza	88.43	715.44
1255	Handcrafted Concrete Pizza	61.88	793.28
1285	Handcrafted Concrete Pizza	60.28	976.96
1297	Handcrafted Concrete Pizza	88.09	338.67
1315	Handcrafted Concrete Pizza	60.62	297.86
1316	Handcrafted Concrete Pizza	83.92	881.98
1466	Handcrafted Concrete Pizza	89.62	479.02
1476	Handcrafted Concrete Pizza	87.54	106.13
1511	Handcrafted Concrete Pizza	31.22	102.05
1254	Handcrafted Cotton Chicken	62.34	218.84
1260	Handcrafted Cotton Chicken	76.88	789.98
1263	Handcrafted Cotton Chicken	47.18	725.55
1334	Handcrafted Cotton Chicken	8.79	994.95
1344	Handcrafted Cotton Chicken	84.10	958.63
1354	Handcrafted Cotton Chicken	50.83	572.53
1366	Handcrafted Cotton Chicken	20.82	76.87
1394	Handcrafted Cotton Chicken	13.86	511.23
1277	Handcrafted Fresh Mouse	43.24	955.72
1282	Handcrafted Fresh Mouse	16.82	403.90
1350	Handcrafted Fresh Mouse	97.28	124.35
1397	Handcrafted Fresh Mouse	8.37	599.46
1529	Handcrafted Fresh Mouse	77.32	998.25
1560	Handcrafted Fresh Mouse	45.20	599.46
1602	Handcrafted Fresh Mouse	98.67	103.64
1254	Handcrafted Frozen Pants	91.69	536.94
1257	Handcrafted Frozen Pants	50.72	972.80
1281	Handcrafted Frozen Pants	21.90	945.84
1289	Handcrafted Frozen Pants	46.51	637.82
1391	Handcrafted Frozen Pants	23.43	246.37
1532	Handcrafted Frozen Pants	60.16	656.44
1599	Handcrafted Frozen Pants	78.79	306.48
1222	Handcrafted Granite Shirt	75.64	94.89
1261	Handcrafted Granite Shirt	20.90	341.77
1314	Handcrafted Granite Shirt	56.92	422.50
1322	Handcrafted Granite Shirt	79.77	160.63
1340	Handcrafted Granite Shirt	67.81	284.28
1383	Handcrafted Granite Shirt	59.68	175.77
1387	Handcrafted Granite Shirt	29.32	414.98
1439	Handcrafted Granite Shirt	55.83	333.79
1541	Handcrafted Granite Shirt	30.57	444.70
1544	Handcrafted Granite Shirt	7.32	694.57
1597	Handcrafted Granite Shirt	3.73	936.67
1317	Handcrafted Metal Keyboard	99.61	933.99
1327	Handcrafted Metal Keyboard	27.75	191.89
1356	Handcrafted Metal Keyboard	91.47	632.17
1386	Handcrafted Metal Keyboard	69.24	417.09
1425	Handcrafted Metal Keyboard	64.90	437.40
1498	Handcrafted Metal Keyboard	11.81	758.73
1519	Handcrafted Metal Keyboard	14.26	311.13
1528	Handcrafted Metal Keyboard	43.95	51.79
1593	Handcrafted Metal Keyboard	96.26	345.15
1226	Handcrafted Plastic Hat	66.61	510.39
1237	Handcrafted Plastic Hat	73.02	304.94
1261	Handcrafted Plastic Hat	40.10	847.53
1289	Handcrafted Plastic Hat	26.93	863.79
1310	Handcrafted Plastic Hat	26.94	263.49
1323	Handcrafted Plastic Hat	75.75	827.42
1353	Handcrafted Plastic Hat	56.50	632.88
1396	Handcrafted Plastic Hat	72.74	130.54
1436	Handcrafted Plastic Hat	72.36	428.53
1497	Handcrafted Plastic Hat	50.07	53.25
1543	Handcrafted Plastic Hat	99.39	38.54
1572	Handcrafted Plastic Hat	93.55	569.41
1577	Handcrafted Plastic Hat	97.62	990.50
1594	Handcrafted Plastic Hat	30.59	763.15
1253	Handcrafted Plastic Hat 1	91.79	865.98
1389	Handcrafted Plastic Hat 1	52.37	475.16
1433	Handcrafted Plastic Hat 1	14.83	166.73
1500	Handcrafted Plastic Hat 1	10.19	53.43
1566	Handcrafted Plastic Hat 1	11.91	280.28
1228	Handcrafted Soft Chair	75.74	491.20
1261	Handcrafted Soft Chair	17.07	622.17
1267	Handcrafted Soft Chair	71.20	479.91
1281	Handcrafted Soft Chair	99.21	203.27
1416	Handcrafted Soft Chair	52.58	981.95
1454	Handcrafted Soft Chair	88.53	715.04
1462	Handcrafted Soft Chair	15.10	883.59
1601	Handcrafted Soft Chair	6.58	881.08
1222	Handcrafted Soft Fish	85.07	539.49
1407	Handcrafted Soft Fish	57.58	36.47
1522	Handcrafted Soft Fish	20.42	632.90
1537	Handcrafted Soft Fish	91.70	96.17
1578	Handcrafted Soft Fish	9.65	511.36
1288	Handcrafted Soft Pants	96.39	172.36
1352	Handcrafted Soft Pants	77.73	216.12
1355	Handcrafted Soft Pants	49.31	817.04
1361	Handcrafted Soft Pants	68.26	676.87
1363	Handcrafted Soft Pants	87.99	406.13
1367	Handcrafted Soft Pants	81.83	984.04
1397	Handcrafted Soft Pants	88.21	469.95
1401	Handcrafted Soft Pants	11.97	376.12
1433	Handcrafted Soft Pants	66.41	744.13
1438	Handcrafted Soft Pants	43.32	154.23
1459	Handcrafted Soft Pants	97.16	93.18
1513	Handcrafted Soft Pants	78.52	857.94
1602	Handcrafted Soft Pants	91.20	133.96
1230	Handcrafted Wooden Pizza	39.02	70.58
1239	Handcrafted Wooden Pizza	89.50	486.62
1277	Handcrafted Wooden Pizza	5.87	128.70
1287	Handcrafted Wooden Pizza	96.58	105.70
1304	Handcrafted Wooden Pizza	24.35	533.79
1313	Handcrafted Wooden Pizza	90.06	470.39
1346	Handcrafted Wooden Pizza	4.02	486.44
1441	Handcrafted Wooden Pizza	51.85	599.77
1449	Handcrafted Wooden Pizza	27.99	575.63
1509	Handcrafted Wooden Pizza	32.25	722.07
1551	Handcrafted Wooden Pizza	86.06	162.05
1210	Handmade Cotton Chips	96.69	543.24
1268	Handmade Cotton Chips	20.73	745.06
1292	Handmade Cotton Chips	55.15	240.24
1298	Handmade Cotton Chips	76.41	32.92
1308	Handmade Cotton Chips	42.15	804.14
1311	Handmade Cotton Chips	76.67	591.51
1319	Handmade Cotton Chips	91.55	72.26
1321	Handmade Cotton Chips	46.92	878.57
1351	Handmade Cotton Chips	33.56	932.50
1353	Handmade Cotton Chips	16.32	925.63
1384	Handmade Cotton Chips	63.31	918.45
1431	Handmade Cotton Chips	51.90	529.43
1456	Handmade Cotton Chips	99.62	206.00
1522	Handmade Cotton Chips	72.83	365.37
1533	Handmade Cotton Chips	65.42	13.01
1551	Handmade Cotton Chips	28.51	109.05
1580	Handmade Cotton Chips	77.02	253.10
1218	Handmade Fresh Chair	56.52	484.80
1248	Handmade Fresh Chair	89.76	541.84
1251	Handmade Fresh Chair	89.41	698.70
1297	Handmade Fresh Chair	96.47	495.27
1298	Handmade Fresh Chair	72.89	489.38
1364	Handmade Fresh Chair	89.64	756.75
1388	Handmade Fresh Chair	48.75	861.28
1432	Handmade Fresh Chair	42.74	862.83
1456	Handmade Fresh Chair	96.92	925.17
1478	Handmade Fresh Chair	86.37	418.92
1568	Handmade Fresh Chair	35.84	882.46
1595	Handmade Fresh Chair	68.73	699.62
1602	Handmade Fresh Chair	62.13	718.93
1241	Handmade Fresh Chicken	64.38	114.24
1266	Handmade Fresh Chicken	94.70	310.18
1312	Handmade Fresh Chicken	62.68	75.30
1375	Handmade Fresh Chicken	74.97	914.23
1470	Handmade Fresh Chicken	34.27	70.92
1473	Handmade Fresh Chicken	96.90	431.69
1515	Handmade Fresh Chicken	60.34	770.00
1536	Handmade Fresh Chicken	74.73	79.55
1571	Handmade Fresh Chicken	64.83	346.97
1572	Handmade Fresh Chicken	63.40	901.66
1579	Handmade Fresh Chicken	72.63	927.53
1580	Handmade Fresh Chicken	47.64	561.29
1606	Handmade Fresh Chicken	77.99	390.46
1270	Handmade Fresh Tuna	75.08	183.62
1302	Handmade Fresh Tuna	70.74	80.91
1354	Handmade Fresh Tuna	94.20	207.63
1368	Handmade Fresh Tuna	4.00	979.63
1387	Handmade Fresh Tuna	44.13	461.47
1415	Handmade Fresh Tuna	72.46	459.83
1478	Handmade Fresh Tuna	12.00	168.45
1488	Handmade Fresh Tuna	74.59	354.13
1519	Handmade Fresh Tuna	76.88	652.85
1261	Handmade Granite Pants	8.70	979.55
1269	Handmade Granite Pants	67.84	162.23
1283	Handmade Granite Pants	26.28	281.67
1301	Handmade Granite Pants	6.82	656.90
1398	Handmade Granite Pants	50.24	600.37
1400	Handmade Granite Pants	97.97	347.38
1520	Handmade Granite Pants	9.07	311.23
1598	Handmade Granite Pants	70.08	188.51
1253	Handmade Plastic Bike	10.12	973.68
1293	Handmade Plastic Bike	91.47	919.23
1320	Handmade Plastic Bike	5.68	818.77
1509	Handmade Plastic Bike	35.24	366.85
1525	Handmade Plastic Bike	70.80	902.62
1534	Handmade Plastic Bike	91.96	265.29
1564	Handmade Plastic Bike	59.80	887.25
1581	Handmade Plastic Bike	30.02	443.72
1264	Handmade Rubber Chair	47.84	812.37
1271	Handmade Rubber Chair	69.36	650.59
1292	Handmade Rubber Chair	37.65	333.99
1330	Handmade Rubber Chair	95.29	218.83
1347	Handmade Rubber Chair	60.82	610.54
1396	Handmade Rubber Chair	72.89	954.40
1411	Handmade Rubber Chair	87.21	10.19
1438	Handmade Rubber Chair	12.27	281.54
1472	Handmade Rubber Chair	33.65	383.77
1482	Handmade Rubber Chair	88.31	644.16
1534	Handmade Rubber Chair	50.09	671.53
1536	Handmade Rubber Chair	76.17	738.47
1567	Handmade Rubber Chair	29.61	371.73
1211	Handmade Rubber Shirt	74.26	483.47
1229	Handmade Rubber Shirt	11.31	887.78
1252	Handmade Rubber Shirt	16.19	89.69
1299	Handmade Rubber Shirt	84.09	243.99
1332	Handmade Rubber Shirt	90.50	652.85
1378	Handmade Rubber Shirt	89.03	147.53
1457	Handmade Rubber Shirt	63.61	286.23
1510	Handmade Rubber Shirt	72.34	205.55
1532	Handmade Rubber Shirt	14.25	235.12
1238	Handmade Soft Towels	43.58	706.55
1373	Handmade Soft Towels	13.58	30.88
1422	Handmade Soft Towels	75.44	704.80
1424	Handmade Soft Towels	69.45	943.24
1565	Handmade Soft Towels	2.67	756.62
1580	Handmade Soft Towels	46.69	660.31
1588	Handmade Soft Towels	57.57	927.21
1605	Handmade Soft Towels	99.56	781.93
1307	Handmade Wooden Bacon	51.55	327.41
1317	Handmade Wooden Bacon	53.89	461.57
1367	Handmade Wooden Bacon	27.22	787.19
1398	Handmade Wooden Bacon	58.10	995.61
1538	Handmade Wooden Bacon	15.54	150.92
1541	Handmade Wooden Bacon	86.63	517.27
1273	Incredible Concrete Chicken	1.39	658.24
1299	Incredible Concrete Chicken	97.98	627.98
1359	Incredible Concrete Chicken	99.12	209.76
1406	Incredible Concrete Chicken	50.92	146.14
1432	Incredible Concrete Chicken	6.61	766.94
1488	Incredible Concrete Chicken	25.19	11.92
1542	Incredible Concrete Chicken	48.71	672.00
1573	Incredible Concrete Chicken	68.00	508.95
1241	Incredible Cotton Ball	14.56	727.78
1340	Incredible Cotton Ball	42.31	222.70
1402	Incredible Cotton Ball	61.58	770.42
1430	Incredible Cotton Ball	99.30	178.30
1447	Incredible Cotton Ball	20.57	253.22
1539	Incredible Cotton Ball	47.45	494.37
1575	Incredible Cotton Ball	9.24	307.46
1592	Incredible Cotton Ball	27.54	789.45
1264	Incredible Fresh Chips	15.92	970.37
1288	Incredible Fresh Chips	25.60	39.11
1359	Incredible Fresh Chips	88.32	854.34
1452	Incredible Fresh Chips	21.59	407.45
1592	Incredible Fresh Chips	10.41	597.38
1265	Incredible Granite Car	97.32	836.35
1273	Incredible Granite Car	22.67	142.03
1358	Incredible Granite Car	88.33	963.56
1392	Incredible Granite Car	66.18	457.54
1425	Incredible Granite Car	9.44	119.00
1472	Incredible Granite Car	85.92	864.08
1573	Incredible Granite Car	89.38	683.69
1588	Incredible Granite Car	58.74	927.33
1226	Incredible Metal Bike	71.74	934.32
1246	Incredible Metal Bike	6.58	790.16
1259	Incredible Metal Bike	24.93	922.09
1413	Incredible Metal Bike	85.84	892.25
1425	Incredible Metal Bike	64.47	154.47
1472	Incredible Metal Bike	43.83	663.97
1499	Incredible Metal Bike	7.85	371.24
1216	Incredible Metal Fish	77.09	237.67
1224	Incredible Metal Fish	79.56	584.01
1273	Incredible Metal Fish	92.02	706.65
1344	Incredible Metal Fish	37.52	422.73
1345	Incredible Metal Fish	10.04	453.33
1405	Incredible Metal Fish	68.59	303.76
1417	Incredible Metal Fish	40.28	466.45
1469	Incredible Metal Fish	22.36	446.10
1491	Incredible Metal Fish	32.39	465.57
1217	Incredible Metal Table	81.70	313.80
1245	Incredible Metal Table	45.40	294.87
1280	Incredible Metal Table	69.16	879.43
1325	Incredible Metal Table	48.91	486.68
1418	Incredible Metal Table	10.76	25.78
1428	Incredible Metal Table	25.92	74.27
1496	Incredible Metal Table	45.70	399.56
1592	Incredible Metal Table	94.09	777.81
1598	Incredible Metal Table	73.76	814.75
1223	Incredible Metal Tuna	10.09	85.11
1268	Incredible Metal Tuna	18.04	672.37
1588	Incredible Metal Tuna	9.64	711.22
1590	Incredible Metal Tuna	81.41	631.18
1601	Incredible Metal Tuna	41.61	195.48
1231	Incredible Rubber Bacon	73.98	618.64
1264	Incredible Rubber Bacon	33.96	99.97
1300	Incredible Rubber Bacon	76.61	579.06
1325	Incredible Rubber Bacon	70.85	72.74
1333	Incredible Rubber Bacon	79.20	551.02
1380	Incredible Rubber Bacon	22.89	505.05
1391	Incredible Rubber Bacon	84.78	156.86
1410	Incredible Rubber Bacon	38.22	629.57
1429	Incredible Rubber Bacon	53.56	16.57
1492	Incredible Rubber Bacon	10.16	301.57
1515	Incredible Rubber Bacon	89.74	544.43
1532	Incredible Rubber Bacon	37.70	672.92
1538	Incredible Rubber Bacon	9.21	61.44
1554	Incredible Rubber Bacon	4.86	798.10
1578	Incredible Rubber Bacon	58.14	281.97
1595	Incredible Rubber Bacon	86.14	148.98
1600	Incredible Rubber Bacon	59.22	385.13
1211	Incredible Rubber Chair	17.90	162.73
1248	Incredible Rubber Chair	98.55	710.71
1347	Incredible Rubber Chair	68.81	198.13
1370	Incredible Rubber Chair	44.98	212.80
1398	Incredible Rubber Chair	82.49	499.58
1402	Incredible Rubber Chair	94.40	620.83
1430	Incredible Rubber Chair	84.00	108.55
1462	Incredible Rubber Chair	10.08	651.78
1567	Incredible Rubber Chair	57.13	773.69
1236	Incredible Rubber Shoes	16.08	770.33
1261	Incredible Rubber Shoes	88.67	147.31
1269	Incredible Rubber Shoes	77.52	78.73
1313	Incredible Rubber Shoes	40.28	112.26
1357	Incredible Rubber Shoes	62.09	492.01
1383	Incredible Rubber Shoes	31.57	49.49
1547	Incredible Rubber Shoes	94.21	303.73
1564	Incredible Rubber Shoes	11.21	971.00
1567	Incredible Rubber Shoes	51.64	36.03
1588	Incredible Rubber Shoes	90.05	801.69
1236	Incredible Steel Cheese	18.05	652.40
1286	Incredible Steel Cheese	73.41	844.27
1321	Incredible Steel Cheese	31.29	430.81
1348	Incredible Steel Cheese	51.70	41.59
1354	Incredible Steel Cheese	26.80	937.71
1401	Incredible Steel Cheese	98.19	688.24
1403	Incredible Steel Cheese	17.17	184.40
1475	Incredible Steel Cheese	72.60	474.06
1484	Incredible Steel Cheese	56.17	852.71
1488	Incredible Steel Cheese	68.18	79.24
1489	Incredible Steel Cheese	99.76	708.10
1514	Incredible Steel Cheese	65.77	208.21
1526	Incredible Steel Cheese	88.39	761.92
1531	Incredible Steel Cheese	32.48	865.34
1532	Incredible Steel Cheese	25.18	809.98
1538	Incredible Steel Cheese	6.32	562.05
1569	Incredible Steel Cheese	23.84	443.88
1588	Incredible Steel Cheese	42.32	441.81
1230	Incredible Steel Sausages	56.43	833.94
1240	Incredible Steel Sausages	75.69	838.84
1264	Incredible Steel Sausages	5.91	930.23
1388	Incredible Steel Sausages	37.08	365.69
1411	Incredible Steel Sausages	48.26	404.56
1474	Incredible Steel Sausages	95.71	298.45
1490	Incredible Steel Sausages	21.39	401.48
1500	Incredible Steel Sausages	92.23	264.38
1506	Incredible Steel Sausages	76.91	657.55
1556	Incredible Steel Sausages	96.07	448.67
1260	Incredible Wooden Computer	59.50	597.99
1266	Incredible Wooden Computer	19.05	860.51
1270	Incredible Wooden Computer	85.80	339.87
1289	Incredible Wooden Computer	28.04	805.62
1339	Incredible Wooden Computer	98.33	764.00
1375	Incredible Wooden Computer	43.21	780.68
1408	Incredible Wooden Computer	25.55	477.68
1416	Incredible Wooden Computer	15.50	11.79
1496	Incredible Wooden Computer	14.22	836.58
1265	Incredible Wooden Soap	39.97	78.51
1286	Incredible Wooden Soap	6.11	198.33
1312	Incredible Wooden Soap	90.25	263.63
1315	Incredible Wooden Soap	42.76	380.76
1361	Incredible Wooden Soap	49.47	273.65
1405	Incredible Wooden Soap	16.50	391.93
1421	Incredible Wooden Soap	71.71	884.31
1528	Incredible Wooden Soap	62.52	231.15
1234	Intelligent Cotton Bacon	20.56	155.45
1304	Intelligent Cotton Bacon	65.30	713.78
1372	Intelligent Cotton Bacon	70.37	452.77
1401	Intelligent Cotton Bacon	1.63	633.07
1519	Intelligent Cotton Bacon	91.65	20.77
1522	Intelligent Cotton Bacon	25.09	181.12
1578	Intelligent Cotton Bacon	36.18	958.63
1607	Intelligent Cotton Bacon	58.92	303.47
1217	Intelligent Fresh Mouse	38.40	977.86
1272	Intelligent Fresh Mouse	81.03	408.23
1273	Intelligent Fresh Mouse	52.13	418.27
1337	Intelligent Fresh Mouse	52.88	557.66
1351	Intelligent Fresh Mouse	24.25	26.09
1380	Intelligent Fresh Mouse	83.57	315.36
1464	Intelligent Fresh Mouse	14.54	196.84
1482	Intelligent Fresh Mouse	10.23	290.78
1560	Intelligent Fresh Mouse	26.24	53.08
1575	Intelligent Fresh Mouse	90.10	966.23
1230	Intelligent Fresh Pizza	72.79	816.51
1241	Intelligent Fresh Pizza	27.55	973.16
1264	Intelligent Fresh Pizza	30.58	719.32
1302	Intelligent Fresh Pizza	50.42	955.26
1312	Intelligent Fresh Pizza	16.74	828.46
1314	Intelligent Fresh Pizza	80.36	218.75
1367	Intelligent Fresh Pizza	7.33	749.99
1403	Intelligent Fresh Pizza	85.91	419.83
1428	Intelligent Fresh Pizza	10.24	284.04
1439	Intelligent Fresh Pizza	75.47	11.73
1469	Intelligent Fresh Pizza	31.70	563.52
1485	Intelligent Fresh Pizza	71.44	31.77
1528	Intelligent Fresh Pizza	26.14	81.05
1557	Intelligent Fresh Pizza	41.31	498.66
1580	Intelligent Fresh Pizza	47.91	652.41
1582	Intelligent Fresh Pizza	82.21	285.45
1588	Intelligent Fresh Pizza	95.57	357.54
1225	Intelligent Granite Chips	97.61	612.35
1332	Intelligent Granite Chips	39.46	148.18
1343	Intelligent Granite Chips	26.95	978.03
1432	Intelligent Granite Chips	20.96	405.24
1446	Intelligent Granite Chips	92.80	997.98
1463	Intelligent Granite Chips	12.22	729.53
1469	Intelligent Granite Chips	47.08	49.90
1525	Intelligent Granite Chips	71.98	56.31
1528	Intelligent Granite Chips	49.81	899.30
1535	Intelligent Granite Chips	89.92	186.46
1551	Intelligent Granite Chips	49.58	661.77
1570	Intelligent Granite Chips	27.33	409.07
1217	Intelligent Granite Sausages	50.32	156.02
1298	Intelligent Granite Sausages	19.22	932.82
1372	Intelligent Granite Sausages	21.29	240.54
1438	Intelligent Granite Sausages	24.13	310.64
1442	Intelligent Granite Sausages	18.46	265.26
1495	Intelligent Granite Sausages	96.73	171.64
1497	Intelligent Granite Sausages	58.21	70.83
1211	Intelligent Metal Chicken	55.80	470.42
1321	Intelligent Metal Chicken	32.84	394.46
1333	Intelligent Metal Chicken	42.38	728.73
1399	Intelligent Metal Chicken	82.06	872.38
1413	Intelligent Metal Chicken	99.81	90.02
1418	Intelligent Metal Chicken	12.01	976.79
1541	Intelligent Metal Chicken	8.36	62.15
1551	Intelligent Metal Chicken	56.28	143.86
1565	Intelligent Metal Chicken	16.40	773.24
1605	Intelligent Metal Chicken	31.32	218.71
1239	Intelligent Plastic Fish	21.84	427.14
1256	Intelligent Plastic Fish	26.94	635.79
1307	Intelligent Plastic Fish	34.11	820.45
1320	Intelligent Plastic Fish	82.23	208.73
1392	Intelligent Plastic Fish	69.77	867.81
1462	Intelligent Plastic Fish	35.59	77.68
1470	Intelligent Plastic Fish	33.98	586.84
1471	Intelligent Plastic Fish	23.44	920.12
1532	Intelligent Plastic Fish	93.89	101.23
1578	Intelligent Plastic Fish	18.50	850.29
1223	Intelligent Plastic Pizza	55.45	247.18
1246	Intelligent Plastic Pizza	12.50	611.83
1302	Intelligent Plastic Pizza	44.16	397.03
1377	Intelligent Plastic Pizza	87.76	575.94
1383	Intelligent Plastic Pizza	69.97	881.54
1396	Intelligent Plastic Pizza	26.88	814.72
1485	Intelligent Plastic Pizza	21.44	631.40
1548	Intelligent Plastic Pizza	4.23	989.80
1600	Intelligent Plastic Pizza	85.52	403.02
1602	Intelligent Plastic Pizza	57.52	801.46
1229	Intelligent Rubber Chair	17.87	222.66
1252	Intelligent Rubber Chair	63.50	676.93
1263	Intelligent Rubber Chair	71.76	56.78
1278	Intelligent Rubber Chair	1.36	780.92
1291	Intelligent Rubber Chair	88.87	918.39
1339	Intelligent Rubber Chair	15.21	277.76
1435	Intelligent Rubber Chair	92.43	262.57
1487	Intelligent Rubber Chair	97.78	464.88
1511	Intelligent Rubber Chair	58.10	161.17
1520	Intelligent Rubber Chair	33.92	71.98
1557	Intelligent Rubber Chair	13.39	582.78
1593	Intelligent Rubber Chair	58.16	520.58
1603	Intelligent Rubber Chair	81.25	269.44
1257	Intelligent Rubber Pizza	93.88	997.71
1415	Intelligent Rubber Pizza	54.05	363.56
1474	Intelligent Rubber Pizza	91.06	900.86
1486	Intelligent Rubber Pizza	6.46	336.58
1216	Intelligent Soft Hat	49.20	260.96
1327	Intelligent Soft Hat	88.97	859.42
1386	Intelligent Soft Hat	97.67	353.64
1431	Intelligent Soft Hat	64.51	361.61
1534	Intelligent Soft Hat	71.21	372.02
1554	Intelligent Soft Hat	92.39	813.31
1238	Intelligent Soft Pizza	28.30	161.00
1265	Intelligent Soft Pizza	10.59	973.97
1267	Intelligent Soft Pizza	28.41	59.83
1275	Intelligent Soft Pizza	9.10	19.44
1293	Intelligent Soft Pizza	61.04	626.55
1297	Intelligent Soft Pizza	93.60	440.15
1306	Intelligent Soft Pizza	53.63	99.43
1340	Intelligent Soft Pizza	80.95	907.76
1415	Intelligent Soft Pizza	68.72	158.87
1461	Intelligent Soft Pizza	45.16	280.86
1495	Intelligent Soft Pizza	86.09	52.78
1578	Intelligent Soft Pizza	30.88	583.33
1597	Intelligent Soft Pizza	92.86	828.20
1211	Intelligent Wooden Salad	16.39	191.84
1220	Intelligent Wooden Salad	5.22	275.97
1223	Intelligent Wooden Salad	75.84	722.24
1227	Intelligent Wooden Salad	36.45	433.00
1283	Intelligent Wooden Salad	77.07	75.52
1343	Intelligent Wooden Salad	62.90	421.15
1360	Intelligent Wooden Salad	15.70	235.19
1407	Intelligent Wooden Salad	42.74	97.87
1441	Intelligent Wooden Salad	8.84	252.18
1459	Intelligent Wooden Salad	68.19	849.29
1495	Intelligent Wooden Salad	24.60	698.91
1502	Intelligent Wooden Salad	34.99	55.98
1520	Intelligent Wooden Salad	8.71	143.13
1296	Licensed Concrete Shoes	46.69	385.42
1305	Licensed Concrete Shoes	2.05	840.71
1339	Licensed Concrete Shoes	16.40	442.17
1361	Licensed Concrete Shoes	13.58	846.71
1388	Licensed Concrete Shoes	99.59	867.10
1446	Licensed Concrete Shoes	89.52	955.81
1450	Licensed Concrete Shoes	63.64	78.78
1460	Licensed Concrete Shoes	64.49	160.23
1500	Licensed Concrete Shoes	11.85	343.45
1572	Licensed Concrete Shoes	36.85	655.27
1597	Licensed Concrete Shoes	51.88	471.95
1410	Licensed Cotton Bacon	43.13	197.70
1427	Licensed Cotton Bacon	69.06	518.03
1448	Licensed Cotton Bacon	85.17	51.07
1483	Licensed Cotton Bacon	7.00	424.92
1536	Licensed Cotton Bacon	77.10	465.69
1545	Licensed Cotton Bacon	88.79	447.78
1549	Licensed Cotton Bacon	45.17	11.78
1554	Licensed Cotton Bacon	35.43	790.25
1224	Licensed Cotton Ball	63.16	854.22
1251	Licensed Cotton Ball	11.54	169.30
1254	Licensed Cotton Ball	84.72	555.33
1255	Licensed Cotton Ball	20.09	692.22
1320	Licensed Cotton Ball	48.95	534.94
1385	Licensed Cotton Ball	30.46	392.53
1446	Licensed Cotton Ball	76.26	25.19
1452	Licensed Cotton Ball	35.91	958.75
1454	Licensed Cotton Ball	40.56	442.41
1569	Licensed Cotton Ball	29.08	561.44
1239	Licensed Fresh Pizza	36.75	374.81
1330	Licensed Fresh Pizza	36.26	482.11
1401	Licensed Fresh Pizza	18.29	555.94
1479	Licensed Fresh Pizza	61.39	686.88
1513	Licensed Fresh Pizza	99.35	449.19
1530	Licensed Fresh Pizza	59.05	968.20
1551	Licensed Fresh Pizza	66.85	772.48
1590	Licensed Fresh Pizza	56.00	18.60
1607	Licensed Fresh Pizza	53.40	782.57
1608	Licensed Fresh Pizza	5.81	316.72
1316	Licensed Frozen Chair	57.96	783.40
1322	Licensed Frozen Chair	52.66	875.02
1346	Licensed Frozen Chair	76.65	630.49
1350	Licensed Frozen Chair	69.14	870.04
1401	Licensed Frozen Chair	99.52	701.99
1440	Licensed Frozen Chair	65.40	154.03
1476	Licensed Frozen Chair	72.47	78.87
1479	Licensed Frozen Chair	61.64	779.17
1540	Licensed Frozen Chair	76.80	631.94
1556	Licensed Frozen Chair	50.34	798.90
1261	Licensed Frozen Computer	12.34	524.77
1302	Licensed Frozen Computer	28.10	521.79
1406	Licensed Frozen Computer	69.99	750.30
1464	Licensed Frozen Computer	15.55	475.97
1475	Licensed Frozen Computer	54.47	847.59
1533	Licensed Frozen Computer	51.08	544.93
1538	Licensed Frozen Computer	86.39	717.51
1548	Licensed Frozen Computer	99.82	439.49
1555	Licensed Frozen Computer	46.07	789.55
1558	Licensed Frozen Computer	49.17	508.14
1584	Licensed Frozen Computer	80.13	803.34
1223	Licensed Frozen Mouse	66.23	897.18
1371	Licensed Frozen Mouse	35.20	800.87
1376	Licensed Frozen Mouse	43.99	616.30
1389	Licensed Frozen Mouse	20.75	675.40
1438	Licensed Frozen Mouse	42.94	549.57
1444	Licensed Frozen Mouse	81.61	988.41
1556	Licensed Frozen Mouse	21.01	526.02
1273	Licensed Granite Keyboard	8.87	846.13
1277	Licensed Granite Keyboard	49.47	806.98
1370	Licensed Granite Keyboard	70.66	96.52
1449	Licensed Granite Keyboard	39.05	862.34
1478	Licensed Granite Keyboard	97.59	77.58
1504	Licensed Granite Keyboard	76.53	319.63
1588	Licensed Granite Keyboard	40.48	224.55
1214	Licensed Plastic Bacon	51.39	266.84
1293	Licensed Plastic Bacon	95.53	566.34
1329	Licensed Plastic Bacon	60.59	357.77
1374	Licensed Plastic Bacon	58.10	306.28
1377	Licensed Plastic Bacon	77.42	821.36
1393	Licensed Plastic Bacon	41.58	727.34
1450	Licensed Plastic Bacon	70.99	589.89
1455	Licensed Plastic Bacon	18.21	506.29
1498	Licensed Plastic Bacon	56.56	695.58
1537	Licensed Plastic Bacon	91.66	714.97
1544	Licensed Plastic Bacon	64.62	189.80
1554	Licensed Plastic Bacon	22.95	22.11
1555	Licensed Plastic Bacon	92.85	435.63
1569	Licensed Plastic Bacon	25.30	496.40
1602	Licensed Plastic Bacon	33.29	301.57
1266	Licensed Plastic Chicken	91.76	62.54
1282	Licensed Plastic Chicken	18.40	50.73
1295	Licensed Plastic Chicken	5.29	481.98
1304	Licensed Plastic Chicken	91.96	311.51
1332	Licensed Plastic Chicken	70.22	952.83
1354	Licensed Plastic Chicken	5.11	844.28
1364	Licensed Plastic Chicken	35.69	352.15
1406	Licensed Plastic Chicken	79.95	605.46
1418	Licensed Plastic Chicken	34.62	329.44
1419	Licensed Plastic Chicken	29.33	905.33
1427	Licensed Plastic Chicken	3.48	494.38
1436	Licensed Plastic Chicken	21.49	579.64
1441	Licensed Plastic Chicken	32.11	102.54
1565	Licensed Plastic Chicken	40.59	398.05
1602	Licensed Plastic Chicken	94.15	434.12
1245	Licensed Plastic Sausages	25.91	213.08
1254	Licensed Plastic Sausages	88.36	489.16
1263	Licensed Plastic Sausages	73.01	767.65
1304	Licensed Plastic Sausages	99.88	504.89
1367	Licensed Plastic Sausages	35.69	922.19
1494	Licensed Plastic Sausages	42.37	864.65
1511	Licensed Plastic Sausages	40.31	486.29
1545	Licensed Plastic Sausages	47.05	86.62
1227	Licensed Plastic Shirt	4.93	580.45
1360	Licensed Plastic Shirt	33.76	941.86
1388	Licensed Plastic Shirt	11.14	98.68
1464	Licensed Plastic Shirt	95.64	745.41
1492	Licensed Plastic Shirt	32.40	807.83
1498	Licensed Plastic Shirt	10.16	881.59
1520	Licensed Plastic Shirt	29.03	212.53
1553	Licensed Plastic Shirt	95.83	898.85
1277	Licensed Rubber Mouse	9.79	67.51
1326	Licensed Rubber Mouse	51.79	384.32
1354	Licensed Rubber Mouse	58.44	36.11
1368	Licensed Rubber Mouse	3.01	870.80
1372	Licensed Rubber Mouse	84.69	107.75
1379	Licensed Rubber Mouse	84.50	412.74
1402	Licensed Rubber Mouse	35.83	981.39
1482	Licensed Rubber Mouse	59.06	926.75
1542	Licensed Rubber Mouse	17.18	687.90
1294	Licensed Soft Computer	25.56	419.81
1316	Licensed Soft Computer	96.56	391.08
1340	Licensed Soft Computer	5.04	700.53
1453	Licensed Soft Computer	80.13	89.86
1470	Licensed Soft Computer	39.82	253.60
1570	Licensed Soft Computer	33.27	38.69
1599	Licensed Soft Computer	90.53	998.47
1607	Licensed Soft Computer	82.52	676.54
1239	Licensed Soft Keyboard	83.99	627.82
1249	Licensed Soft Keyboard	8.72	995.52
1285	Licensed Soft Keyboard	74.91	911.46
1388	Licensed Soft Keyboard	84.79	245.16
1392	Licensed Soft Keyboard	61.37	427.42
1457	Licensed Soft Keyboard	83.12	850.44
1460	Licensed Soft Keyboard	43.10	124.38
1465	Licensed Soft Keyboard	36.79	940.07
1500	Licensed Soft Keyboard	61.04	616.53
1551	Licensed Soft Keyboard	6.02	780.20
1593	Licensed Soft Keyboard	17.11	121.62
1602	Licensed Soft Keyboard	88.62	153.35
1227	Licensed Steel Bacon	80.28	750.92
1259	Licensed Steel Bacon	43.35	347.23
1285	Licensed Steel Bacon	25.48	387.95
1321	Licensed Steel Bacon	81.25	174.78
1332	Licensed Steel Bacon	54.06	997.45
1335	Licensed Steel Bacon	68.17	510.84
1356	Licensed Steel Bacon	19.10	953.82
1436	Licensed Steel Bacon	58.94	638.27
1478	Licensed Steel Bacon	15.78	411.98
1513	Licensed Steel Bacon	68.83	226.03
1541	Licensed Steel Bacon	84.16	553.34
1551	Licensed Steel Bacon	97.02	291.38
1574	Licensed Steel Bacon	75.67	831.02
1215	Licensed Steel Fish	54.93	863.27
1242	Licensed Steel Fish	19.19	540.20
1269	Licensed Steel Fish	10.41	95.33
1287	Licensed Steel Fish	40.25	518.74
1292	Licensed Steel Fish	44.90	421.25
1343	Licensed Steel Fish	92.95	360.92
1362	Licensed Steel Fish	54.49	116.19
1402	Licensed Steel Fish	95.09	948.38
1492	Licensed Steel Fish	93.16	842.97
1500	Licensed Steel Fish	10.15	33.68
1513	Licensed Steel Fish	10.27	19.27
1537	Licensed Steel Fish	6.70	57.54
1262	Licensed Steel Shoes	87.67	98.07
1292	Licensed Steel Shoes	84.93	214.76
1296	Licensed Steel Shoes	86.57	254.14
1315	Licensed Steel Shoes	22.95	928.36
1375	Licensed Steel Shoes	41.05	968.38
1389	Licensed Steel Shoes	50.34	359.19
1454	Licensed Steel Shoes	10.25	198.32
1486	Licensed Steel Shoes	51.81	222.78
1500	Licensed Steel Shoes	92.44	168.22
1505	Licensed Steel Shoes	11.64	815.23
1515	Licensed Steel Shoes	57.64	893.28
1523	Licensed Steel Shoes	79.13	975.51
1524	Licensed Steel Shoes	62.34	203.40
1258	Licensed Wooden Cheese	4.55	637.43
1319	Licensed Wooden Cheese	44.18	433.83
1327	Licensed Wooden Cheese	61.80	516.30
1331	Licensed Wooden Cheese	90.32	734.07
1335	Licensed Wooden Cheese	22.69	856.38
1339	Licensed Wooden Cheese	61.95	559.97
1358	Licensed Wooden Cheese	22.98	996.24
1423	Licensed Wooden Cheese	63.75	251.56
1429	Licensed Wooden Cheese	55.56	564.18
1446	Licensed Wooden Cheese	33.38	585.73
1335	Licensed Wooden Sausages	23.80	429.13
1418	Licensed Wooden Sausages	90.71	990.85
1505	Licensed Wooden Sausages	25.89	361.65
1559	Licensed Wooden Sausages	47.98	599.24
1565	Licensed Wooden Sausages	1.24	512.15
1609	Licensed Wooden Sausages	45.98	650.31
1260	Licensed Wooden Towels	52.74	750.07
1451	Licensed Wooden Towels	80.32	773.42
1553	Licensed Wooden Towels	99.64	283.42
1570	Licensed Wooden Towels	2.54	92.22
1599	Licensed Wooden Towels	73.67	20.71
1603	Licensed Wooden Towels	35.35	206.13
1284	Practical Concrete Salad	84.74	37.20
1337	Practical Concrete Salad	70.80	581.83
1339	Practical Concrete Salad	90.94	438.70
1407	Practical Concrete Salad	70.32	502.54
1495	Practical Concrete Salad	42.37	78.98
1509	Practical Concrete Salad	85.76	721.48
1260	Practical Cotton Gloves	13.90	469.73
1284	Practical Cotton Gloves	74.78	131.71
1336	Practical Cotton Gloves	11.36	544.62
1370	Practical Cotton Gloves	32.95	223.62
1388	Practical Cotton Gloves	47.42	494.05
1508	Practical Cotton Gloves	16.65	852.51
1215	Practical Cotton Keyboard	39.52	496.28
1229	Practical Cotton Keyboard	43.11	801.24
1267	Practical Cotton Keyboard	29.16	870.58
1318	Practical Cotton Keyboard	31.99	728.59
1349	Practical Cotton Keyboard	52.17	81.72
1356	Practical Cotton Keyboard	19.28	68.72
1390	Practical Cotton Keyboard	96.12	940.35
1447	Practical Cotton Keyboard	45.67	129.53
1463	Practical Cotton Keyboard	4.13	378.68
1514	Practical Cotton Keyboard	40.91	512.18
1539	Practical Cotton Keyboard	52.63	110.40
1550	Practical Cotton Keyboard	91.96	623.05
1591	Practical Cotton Keyboard	21.67	600.89
1222	Practical Fresh Chips	14.71	684.14
1272	Practical Fresh Chips	78.98	764.07
1278	Practical Fresh Chips	83.50	448.13
1286	Practical Fresh Chips	31.10	916.16
1322	Practical Fresh Chips	35.72	47.09
1325	Practical Fresh Chips	28.14	44.37
1333	Practical Fresh Chips	58.19	290.40
1353	Practical Fresh Chips	75.18	749.52
1361	Practical Fresh Chips	28.41	346.29
1447	Practical Fresh Chips	39.55	345.79
1503	Practical Fresh Chips	3.05	668.39
1553	Practical Fresh Chips	28.34	111.14
1251	Practical Fresh Keyboard	2.82	562.93
1256	Practical Fresh Keyboard	56.39	728.69
1271	Practical Fresh Keyboard	83.94	965.74
1307	Practical Fresh Keyboard	87.51	224.73
1372	Practical Fresh Keyboard	30.84	44.80
1406	Practical Fresh Keyboard	9.06	76.14
1486	Practical Fresh Keyboard	2.47	485.70
1528	Practical Fresh Keyboard	82.85	294.20
1541	Practical Fresh Keyboard	16.83	721.00
1599	Practical Fresh Keyboard	28.86	38.55
1609	Practical Fresh Keyboard	99.91	828.38
1210	Practical Metal Hat	59.13	651.13
1267	Practical Metal Hat	21.66	629.11
1269	Practical Metal Hat	19.20	669.97
1306	Practical Metal Hat	98.55	915.03
1327	Practical Metal Hat	42.90	65.14
1343	Practical Metal Hat	44.00	618.28
1376	Practical Metal Hat	61.01	561.44
1381	Practical Metal Hat	28.96	393.76
1387	Practical Metal Hat	31.02	192.23
1404	Practical Metal Hat	10.68	245.68
1423	Practical Metal Hat	42.72	554.58
1490	Practical Metal Hat	72.69	465.92
1520	Practical Metal Hat	82.65	322.92
1532	Practical Metal Hat	89.35	14.03
1537	Practical Metal Hat	76.71	117.87
1238	Practical Plastic Mouse	80.25	195.17
1313	Practical Plastic Mouse	69.40	468.06
1351	Practical Plastic Mouse	17.84	307.70
1368	Practical Plastic Mouse	84.57	10.42
1378	Practical Plastic Mouse	89.25	81.17
1422	Practical Plastic Mouse	42.87	505.91
1475	Practical Plastic Mouse	90.06	94.85
1576	Practical Plastic Mouse	87.85	908.57
1228	Practical Plastic Shirt	78.53	969.39
1243	Practical Plastic Shirt	55.12	885.31
1344	Practical Plastic Shirt	84.66	369.16
1459	Practical Plastic Shirt	5.20	352.29
1470	Practical Plastic Shirt	48.00	65.55
1578	Practical Plastic Shirt	52.95	327.56
1595	Practical Plastic Shirt	72.80	694.65
1601	Practical Plastic Shirt	49.83	274.65
1219	Practical Soft Bacon	52.90	371.00
1225	Practical Soft Bacon	75.18	361.67
1273	Practical Soft Bacon	23.67	591.36
1324	Practical Soft Bacon	54.16	935.63
1326	Practical Soft Bacon	22.01	512.23
1370	Practical Soft Bacon	78.63	306.45
1373	Practical Soft Bacon	27.88	156.49
1381	Practical Soft Bacon	1.21	817.12
1475	Practical Soft Bacon	52.80	240.24
1486	Practical Soft Bacon	78.69	614.11
1492	Practical Soft Bacon	88.69	978.44
1565	Practical Soft Bacon	22.86	600.60
1570	Practical Soft Bacon	33.84	790.92
1581	Practical Soft Bacon	98.82	857.09
1585	Practical Soft Bacon	48.25	449.23
1596	Practical Soft Bacon	4.28	676.07
1234	Practical Soft Shirt	58.78	945.16
1250	Practical Soft Shirt	47.27	929.46
1376	Practical Soft Shirt	30.05	891.22
1403	Practical Soft Shirt	76.74	265.44
1410	Practical Soft Shirt	35.87	690.03
1421	Practical Soft Shirt	14.85	48.27
1481	Practical Soft Shirt	11.42	170.07
1490	Practical Soft Shirt	6.89	222.89
1500	Practical Soft Shirt	75.59	122.65
1537	Practical Soft Shirt	61.02	759.44
1561	Practical Soft Shirt	53.92	682.78
1591	Practical Soft Shirt	72.96	657.36
1603	Practical Soft Shirt	49.78	456.06
1273	Refined Concrete Pants	61.88	704.39
1293	Refined Concrete Pants	62.65	773.65
1375	Refined Concrete Pants	98.86	427.17
1386	Refined Concrete Pants	15.18	411.68
1440	Refined Concrete Pants	48.48	278.58
1470	Refined Concrete Pants	83.29	503.50
1526	Refined Concrete Pants	47.20	269.21
1542	Refined Concrete Pants	50.67	345.48
1559	Refined Concrete Pants	71.41	564.08
1235	Refined Cotton Soap	50.67	362.68
1284	Refined Cotton Soap	36.91	180.42
1314	Refined Cotton Soap	78.38	163.60
1389	Refined Cotton Soap	57.37	248.34
1422	Refined Cotton Soap	65.66	856.10
1437	Refined Cotton Soap	60.17	109.08
1443	Refined Cotton Soap	90.51	150.49
1512	Refined Cotton Soap	10.34	629.46
1223	Refined Fresh Chair	54.71	79.63
1270	Refined Fresh Chair	64.13	380.68
1280	Refined Fresh Chair	88.27	306.78
1292	Refined Fresh Chair	72.87	119.55
1335	Refined Fresh Chair	21.36	569.09
1348	Refined Fresh Chair	99.79	640.16
1477	Refined Fresh Chair	28.02	292.98
1496	Refined Fresh Chair	54.88	709.53
1519	Refined Fresh Chair	72.91	162.94
1536	Refined Fresh Chair	16.24	758.06
1577	Refined Fresh Chair	99.16	244.37
1589	Refined Fresh Chair	87.26	834.99
1596	Refined Fresh Chair	18.71	564.31
1225	Refined Fresh Chips	73.17	929.91
1267	Refined Fresh Chips	71.34	410.87
1268	Refined Fresh Chips	5.32	74.91
1338	Refined Fresh Chips	77.01	507.36
1349	Refined Fresh Chips	5.27	73.18
1416	Refined Fresh Chips	16.18	425.51
1459	Refined Fresh Chips	67.76	432.06
1466	Refined Fresh Chips	35.37	843.02
1487	Refined Fresh Chips	1.95	797.75
1506	Refined Fresh Chips	77.58	658.61
1554	Refined Fresh Chips	50.01	897.39
1562	Refined Fresh Chips	75.03	405.39
1286	Refined Rubber Pants	86.69	244.29
1361	Refined Rubber Pants	76.87	542.66
1367	Refined Rubber Pants	55.42	742.67
1370	Refined Rubber Pants	14.30	678.35
1384	Refined Rubber Pants	69.79	502.87
1430	Refined Rubber Pants	9.15	600.35
1447	Refined Rubber Pants	65.88	656.39
1458	Refined Rubber Pants	52.68	167.06
1533	Refined Rubber Pants	88.29	170.53
1540	Refined Rubber Pants	62.45	892.12
1563	Refined Rubber Pants	2.72	218.24
1303	Refined Steel Fish	25.80	174.62
1339	Refined Steel Fish	83.41	824.17
1373	Refined Steel Fish	63.55	753.58
1449	Refined Steel Fish	59.36	959.19
1469	Refined Steel Fish	95.86	233.67
1539	Refined Steel Fish	81.58	649.93
1253	Refined Steel Mouse	65.70	329.09
1314	Refined Steel Mouse	7.15	189.07
1347	Refined Steel Mouse	57.81	293.51
1348	Refined Steel Mouse	99.41	950.29
1275	Refined Wooden Car	87.03	615.19
1301	Refined Wooden Car	34.83	882.65
1352	Refined Wooden Car	62.23	523.39
1401	Refined Wooden Car	63.05	784.90
1449	Refined Wooden Car	15.52	938.38
1278	Refined Wooden Table	10.38	868.94
1302	Refined Wooden Table	63.20	258.86
1360	Refined Wooden Table	33.84	103.32
1373	Refined Wooden Table	35.24	749.16
1385	Refined Wooden Table	18.76	562.81
1451	Refined Wooden Table	48.94	69.68
1491	Refined Wooden Table	87.12	300.55
1516	Refined Wooden Table	4.46	645.19
1530	Refined Wooden Table	31.50	478.35
1549	Refined Wooden Table	3.40	196.83
1575	Refined Wooden Table	88.23	14.70
1589	Refined Wooden Table	5.37	394.32
1593	Refined Wooden Table	68.03	930.80
1228	Rustic Concrete Chair	45.19	964.79
1230	Rustic Concrete Chair	69.24	875.12
1310	Rustic Concrete Chair	19.17	582.57
1345	Rustic Concrete Chair	91.51	594.74
1348	Rustic Concrete Chair	51.04	955.78
1432	Rustic Concrete Chair	82.55	210.50
1458	Rustic Concrete Chair	56.56	673.44
1510	Rustic Concrete Chair	16.91	747.31
1587	Rustic Concrete Chair	72.47	439.75
1234	Rustic Concrete Shirt	35.73	750.24
1246	Rustic Concrete Shirt	27.75	399.03
1266	Rustic Concrete Shirt	90.82	863.13
1283	Rustic Concrete Shirt	28.75	373.39
1322	Rustic Concrete Shirt	80.69	362.58
1325	Rustic Concrete Shirt	49.91	485.26
1347	Rustic Concrete Shirt	86.91	201.33
1417	Rustic Concrete Shirt	33.06	33.09
1509	Rustic Concrete Shirt	8.32	962.12
1564	Rustic Concrete Shirt	14.53	35.35
1609	Rustic Concrete Shirt	4.47	369.22
1234	Rustic Frozen Bacon	29.84	185.61
1300	Rustic Frozen Bacon	50.77	60.58
1318	Rustic Frozen Bacon	86.85	166.20
1328	Rustic Frozen Bacon	17.19	40.06
1422	Rustic Frozen Bacon	25.77	317.83
1441	Rustic Frozen Bacon	36.77	788.25
1565	Rustic Frozen Bacon	38.09	653.41
1582	Rustic Frozen Bacon	87.31	104.45
1222	Rustic Frozen Ball	36.04	421.24
1242	Rustic Frozen Ball	46.50	698.66
1361	Rustic Frozen Ball	49.50	186.09
1435	Rustic Frozen Ball	66.75	59.35
1473	Rustic Frozen Ball	45.54	472.96
1498	Rustic Frozen Ball	33.90	23.31
1501	Rustic Frozen Ball	97.07	677.03
1508	Rustic Frozen Ball	91.38	162.56
1543	Rustic Frozen Ball	90.29	944.55
1213	Rustic Frozen Chair	46.39	938.47
1270	Rustic Frozen Chair	81.84	542.23
1285	Rustic Frozen Chair	54.99	934.17
1318	Rustic Frozen Chair	75.31	691.27
1363	Rustic Frozen Chair	45.68	84.45
1408	Rustic Frozen Chair	66.32	61.41
1423	Rustic Frozen Chair	53.01	174.64
1436	Rustic Frozen Chair	57.51	761.29
1437	Rustic Frozen Chair	52.72	818.69
1464	Rustic Frozen Chair	55.66	108.99
1471	Rustic Frozen Chair	63.95	80.85
1489	Rustic Frozen Chair	36.68	103.59
1508	Rustic Frozen Chair	13.78	146.94
1512	Rustic Frozen Chair	72.25	949.38
1558	Rustic Frozen Chair	7.14	593.03
1564	Rustic Frozen Chair	32.09	351.69
1221	Rustic Granite Cheese	10.16	598.65
1295	Rustic Granite Cheese	42.76	758.33
1330	Rustic Granite Cheese	95.24	828.91
1408	Rustic Granite Cheese	83.10	690.05
1465	Rustic Granite Cheese	27.90	474.47
1547	Rustic Granite Cheese	31.03	93.47
1230	Rustic Metal Chips	42.98	58.35
1254	Rustic Metal Chips	79.27	39.55
1376	Rustic Metal Chips	44.65	665.69
1401	Rustic Metal Chips	6.01	388.47
1454	Rustic Metal Chips	87.35	748.28
1500	Rustic Metal Chips	41.72	133.76
1506	Rustic Metal Chips	95.12	864.04
1551	Rustic Metal Chips	39.25	114.94
1583	Rustic Metal Chips	68.97	165.07
1212	Rustic Metal Sausages	68.37	808.31
1213	Rustic Metal Sausages	30.04	495.76
1414	Rustic Metal Sausages	60.74	421.60
1442	Rustic Metal Sausages	32.74	172.07
1448	Rustic Metal Sausages	25.89	138.21
1481	Rustic Metal Sausages	46.45	770.99
1516	Rustic Metal Sausages	46.44	116.77
1544	Rustic Metal Sausages	98.53	849.05
1227	Rustic Rubber Fish	1.94	291.86
1246	Rustic Rubber Fish	81.91	221.15
1255	Rustic Rubber Fish	34.25	480.15
1295	Rustic Rubber Fish	23.33	712.90
1354	Rustic Rubber Fish	79.78	275.47
1385	Rustic Rubber Fish	75.59	904.90
1409	Rustic Rubber Fish	48.17	959.58
1505	Rustic Rubber Fish	83.76	19.42
1551	Rustic Rubber Fish	69.14	45.21
1577	Rustic Rubber Fish	74.36	20.73
1591	Rustic Rubber Fish	77.16	40.30
1600	Rustic Rubber Fish	63.00	885.80
1210	Rustic Rubber Shirt	99.52	208.36
1358	Rustic Rubber Shirt	74.03	231.41
1406	Rustic Rubber Shirt	57.07	157.14
1417	Rustic Rubber Shirt	48.15	954.38
1463	Rustic Rubber Shirt	82.71	909.64
1514	Rustic Rubber Shirt	21.64	551.15
1556	Rustic Rubber Shirt	84.16	573.21
1583	Rustic Rubber Shirt	23.22	60.44
1215	Rustic Soft Chips	71.84	242.66
1224	Rustic Soft Chips	96.79	592.40
1305	Rustic Soft Chips	98.85	592.45
1353	Rustic Soft Chips	74.84	462.18
1355	Rustic Soft Chips	31.20	329.97
1368	Rustic Soft Chips	57.48	115.42
1402	Rustic Soft Chips	91.10	165.96
1443	Rustic Soft Chips	64.43	52.16
1471	Rustic Soft Chips	50.47	851.34
1535	Rustic Soft Chips	9.36	247.76
1540	Rustic Soft Chips	60.11	167.10
1565	Rustic Soft Chips	26.28	27.36
1599	Rustic Soft Chips	22.55	693.96
1210	Rustic Wooden Hat	38.22	259.56
1256	Rustic Wooden Hat	9.92	190.33
1270	Rustic Wooden Hat	18.92	926.76
1309	Rustic Wooden Hat	89.45	987.41
1345	Rustic Wooden Hat	4.87	103.77
1370	Rustic Wooden Hat	8.91	152.83
1444	Rustic Wooden Hat	8.65	288.38
1567	Rustic Wooden Hat	43.70	644.24
1569	Rustic Wooden Hat	5.96	594.23
1213	Sleek Cotton Cheese	91.60	189.21
1214	Sleek Cotton Cheese	45.01	101.52
1232	Sleek Cotton Cheese	18.99	992.92
1266	Sleek Cotton Cheese	70.21	927.67
1275	Sleek Cotton Cheese	39.44	379.42
1319	Sleek Cotton Cheese	43.64	714.64
1364	Sleek Cotton Cheese	53.89	27.48
1379	Sleek Cotton Cheese	55.07	49.11
1382	Sleek Cotton Cheese	67.52	964.53
1428	Sleek Cotton Cheese	90.77	704.05
1433	Sleek Cotton Cheese	80.75	279.15
1454	Sleek Cotton Cheese	49.05	266.55
1493	Sleek Cotton Cheese	98.41	429.38
1548	Sleek Cotton Cheese	40.22	729.70
1563	Sleek Cotton Cheese	79.04	767.91
1310	Sleek Cotton Soap	30.64	650.82
1312	Sleek Cotton Soap	78.62	87.64
1351	Sleek Cotton Soap	6.78	448.06
1365	Sleek Cotton Soap	25.16	838.84
1392	Sleek Cotton Soap	21.87	990.05
1429	Sleek Cotton Soap	10.97	560.57
1537	Sleek Cotton Soap	79.90	535.47
1582	Sleek Cotton Soap	95.36	661.45
1583	Sleek Cotton Soap	78.40	708.68
1236	Sleek Fresh Bacon	13.72	523.12
1239	Sleek Fresh Bacon	18.74	134.48
1254	Sleek Fresh Bacon	55.54	739.09
1263	Sleek Fresh Bacon	19.08	340.05
1264	Sleek Fresh Bacon	22.40	288.00
1291	Sleek Fresh Bacon	21.73	929.41
1349	Sleek Fresh Bacon	59.03	698.16
1370	Sleek Fresh Bacon	86.96	794.12
1385	Sleek Fresh Bacon	21.53	91.71
1405	Sleek Fresh Bacon	16.29	771.78
1411	Sleek Fresh Bacon	62.86	946.78
1480	Sleek Fresh Bacon	50.72	907.04
1495	Sleek Fresh Bacon	16.02	752.41
1540	Sleek Fresh Bacon	82.57	801.57
1571	Sleek Fresh Bacon	71.99	618.41
1585	Sleek Fresh Bacon	16.17	520.68
1606	Sleek Fresh Bacon	36.79	461.37
1240	Sleek Fresh Keyboard	24.23	29.94
1251	Sleek Fresh Keyboard	1.16	81.19
1253	Sleek Fresh Keyboard	16.70	132.41
1265	Sleek Fresh Keyboard	17.69	458.91
1350	Sleek Fresh Keyboard	56.75	474.47
1354	Sleek Fresh Keyboard	85.24	394.99
1431	Sleek Fresh Keyboard	48.28	164.18
1461	Sleek Fresh Keyboard	15.90	293.70
1518	Sleek Fresh Keyboard	17.34	42.38
1549	Sleek Fresh Keyboard	23.73	273.16
1556	Sleek Fresh Keyboard	55.78	70.60
1577	Sleek Fresh Keyboard	31.54	275.93
1229	Sleek Frozen Chicken	58.18	206.42
1317	Sleek Frozen Chicken	44.67	181.58
1353	Sleek Frozen Chicken	69.31	68.50
1372	Sleek Frozen Chicken	95.58	540.39
1377	Sleek Frozen Chicken	77.52	868.97
1507	Sleek Frozen Chicken	51.23	153.57
1580	Sleek Frozen Chicken	19.06	344.73
1279	Sleek Granite Car	92.82	879.52
1288	Sleek Granite Car	18.08	69.84
1306	Sleek Granite Car	46.43	660.46
1311	Sleek Granite Car	5.31	619.61
1472	Sleek Granite Car	60.43	432.27
1474	Sleek Granite Car	4.13	886.46
1475	Sleek Granite Car	80.30	206.53
1578	Sleek Granite Car	54.80	271.38
1222	Sleek Granite Fish	16.85	377.61
1227	Sleek Granite Fish	80.26	794.15
1236	Sleek Granite Fish	77.60	172.98
1289	Sleek Granite Fish	75.30	39.10
1300	Sleek Granite Fish	86.39	465.78
1314	Sleek Granite Fish	71.18	972.02
1345	Sleek Granite Fish	13.14	392.07
1360	Sleek Granite Fish	35.98	565.79
1403	Sleek Granite Fish	66.95	957.94
1414	Sleek Granite Fish	21.36	520.03
1459	Sleek Granite Fish	14.25	308.00
1525	Sleek Granite Fish	30.86	21.71
1538	Sleek Granite Fish	82.32	610.35
1550	Sleek Granite Fish	40.63	897.73
1560	Sleek Granite Fish	58.12	805.74
1582	Sleek Granite Fish	35.91	104.15
1589	Sleek Granite Fish	62.27	61.57
1216	Sleek Granite Tuna	89.70	691.55
1249	Sleek Granite Tuna	22.67	996.31
1333	Sleek Granite Tuna	73.95	824.39
1351	Sleek Granite Tuna	12.18	982.67
1425	Sleek Granite Tuna	62.09	86.50
1447	Sleek Granite Tuna	35.84	687.90
1560	Sleek Granite Tuna	79.15	66.75
1237	Sleek Metal Soap	97.41	404.23
1253	Sleek Metal Soap	38.80	641.02
1284	Sleek Metal Soap	50.40	502.45
1324	Sleek Metal Soap	89.77	770.91
1326	Sleek Metal Soap	46.01	877.67
1354	Sleek Metal Soap	71.57	216.14
1364	Sleek Metal Soap	74.22	947.08
1400	Sleek Metal Soap	27.26	652.61
1407	Sleek Metal Soap	65.39	901.17
1432	Sleek Metal Soap	25.54	392.30
1433	Sleek Metal Soap	16.40	851.66
1526	Sleek Metal Soap	86.91	939.51
1242	Small Cotton Salad	77.32	327.47
1376	Small Cotton Salad	40.82	328.22
1399	Small Cotton Salad	65.45	519.28
1400	Small Cotton Salad	57.38	169.92
1412	Small Cotton Salad	27.17	935.12
1424	Small Cotton Salad	73.55	627.81
1430	Small Cotton Salad	12.09	133.20
1444	Small Cotton Salad	62.03	705.45
1494	Small Cotton Salad	22.31	134.68
1568	Small Cotton Salad	25.88	704.15
1248	Small Fresh Car	92.54	125.01
1278	Small Fresh Car	8.13	953.79
1287	Small Fresh Car	45.71	83.56
1321	Small Fresh Car	87.67	540.39
1331	Small Fresh Car	33.65	889.47
1350	Small Fresh Car	95.96	15.61
1403	Small Fresh Car	87.29	80.32
1435	Small Fresh Car	5.03	894.43
1442	Small Fresh Car	76.56	16.08
1473	Small Fresh Car	51.42	133.38
1480	Small Fresh Car	96.97	108.30
1525	Small Fresh Car	10.47	563.91
1543	Small Fresh Car	53.65	228.42
1555	Small Fresh Car	77.24	495.80
1594	Small Fresh Car	24.41	407.94
1232	Small Frozen Bike	48.15	559.37
1322	Small Frozen Bike	96.47	723.68
1367	Small Frozen Bike	20.88	428.57
1376	Small Frozen Bike	60.70	384.29
1381	Small Frozen Bike	68.67	681.05
1405	Small Frozen Bike	84.95	377.13
1420	Small Frozen Bike	19.63	514.07
1425	Small Frozen Bike	89.72	911.13
1476	Small Frozen Bike	37.40	132.65
1517	Small Frozen Bike	63.82	985.99
1234	Small Plastic Bike	19.04	414.69
1274	Small Plastic Bike	48.04	604.31
1309	Small Plastic Bike	24.34	975.86
1327	Small Plastic Bike	67.02	251.48
1384	Small Plastic Bike	96.11	642.14
1436	Small Plastic Bike	91.31	462.17
1519	Small Plastic Bike	65.47	104.73
1558	Small Plastic Bike	79.07	145.20
1574	Small Plastic Bike	38.31	854.40
1240	Small Plastic Cheese	71.60	979.18
1285	Small Plastic Cheese	26.62	755.57
1340	Small Plastic Cheese	88.39	513.95
1369	Small Plastic Cheese	78.39	624.52
1392	Small Plastic Cheese	67.19	906.23
1400	Small Plastic Cheese	71.07	242.21
1402	Small Plastic Cheese	19.89	16.77
1449	Small Plastic Cheese	86.94	770.24
1451	Small Plastic Cheese	15.33	764.69
1510	Small Plastic Cheese	38.40	182.53
1540	Small Plastic Cheese	48.90	25.48
1604	Small Plastic Cheese	25.63	620.25
1256	Small Soft Gloves	42.10	29.84
1276	Small Soft Gloves	37.97	290.60
1296	Small Soft Gloves	11.67	993.60
1307	Small Soft Gloves	17.05	700.79
1308	Small Soft Gloves	58.42	318.73
1367	Small Soft Gloves	57.40	856.40
1377	Small Soft Gloves	8.77	686.37
1418	Small Soft Gloves	50.80	656.09
1446	Small Soft Gloves	34.48	916.22
1453	Small Soft Gloves	1.08	941.48
1455	Small Soft Gloves	25.61	435.87
1466	Small Soft Gloves	45.81	723.19
1469	Small Soft Gloves	90.07	98.63
1485	Small Soft Gloves	71.37	850.30
1490	Small Soft Gloves	19.16	636.68
1265	Small Soft Pizza	6.46	111.14
1279	Small Soft Pizza	65.41	758.45
1302	Small Soft Pizza	37.04	345.01
1338	Small Soft Pizza	40.69	617.45
1384	Small Soft Pizza	76.65	330.31
1394	Small Soft Pizza	13.46	232.49
1396	Small Soft Pizza	68.90	125.97
1454	Small Soft Pizza	3.07	962.71
1461	Small Soft Pizza	75.89	307.01
1488	Small Soft Pizza	48.42	380.53
1515	Small Soft Pizza	38.34	902.78
1574	Small Soft Pizza	5.42	242.46
1222	Tasty Concrete Shoes	40.75	497.25
1261	Tasty Concrete Shoes	48.27	303.90
1273	Tasty Concrete Shoes	46.50	727.63
1274	Tasty Concrete Shoes	5.80	517.61
1349	Tasty Concrete Shoes	56.91	918.37
1360	Tasty Concrete Shoes	57.75	719.07
1372	Tasty Concrete Shoes	92.05	380.13
1377	Tasty Concrete Shoes	69.04	514.72
1381	Tasty Concrete Shoes	99.04	149.24
1382	Tasty Concrete Shoes	59.40	554.03
1473	Tasty Concrete Shoes	88.56	229.14
1497	Tasty Concrete Shoes	92.57	556.74
1507	Tasty Concrete Shoes	4.39	433.71
1533	Tasty Concrete Shoes	63.86	470.78
1512	Tasty Soft Hat	33.13	779.01
1562	Tasty Concrete Shoes	72.00	549.98
1221	Tasty Concrete Tuna	56.72	318.09
1291	Tasty Concrete Tuna	12.71	84.68
1355	Tasty Concrete Tuna	78.47	563.46
1360	Tasty Concrete Tuna	20.61	616.65
1376	Tasty Concrete Tuna	43.78	676.23
1390	Tasty Concrete Tuna	49.88	241.29
1487	Tasty Concrete Tuna	9.95	659.75
1516	Tasty Concrete Tuna	47.29	660.11
1603	Tasty Concrete Tuna	21.85	890.24
1298	Tasty Cotton Keyboard	13.50	222.25
1328	Tasty Cotton Keyboard	87.86	642.01
1385	Tasty Cotton Keyboard	77.44	369.64
1533	Tasty Cotton Keyboard	99.06	167.02
1541	Tasty Cotton Keyboard	42.29	613.62
1594	Tasty Cotton Keyboard	18.44	47.41
1602	Tasty Cotton Keyboard	49.33	576.41
1289	Tasty Fresh Computer	9.44	711.27
1307	Tasty Fresh Computer	91.26	279.85
1417	Tasty Fresh Computer	33.08	936.70
1478	Tasty Fresh Computer	22.77	340.19
1502	Tasty Fresh Computer	70.78	358.27
1534	Tasty Fresh Computer	16.19	157.01
1550	Tasty Fresh Computer	24.60	111.20
1269	Tasty Fresh Salad	38.43	533.54
1327	Tasty Fresh Salad	50.41	957.69
1411	Tasty Fresh Salad	39.35	640.34
1427	Tasty Fresh Salad	67.50	326.11
1485	Tasty Fresh Salad	55.65	880.75
1488	Tasty Fresh Salad	91.50	454.87
1534	Tasty Fresh Salad	38.06	702.16
1552	Tasty Fresh Salad	50.69	57.71
1218	Tasty Granite Cheese	27.89	846.18
1225	Tasty Granite Cheese	16.67	705.95
1236	Tasty Granite Cheese	28.49	113.12
1329	Tasty Granite Cheese	54.63	335.90
1330	Tasty Granite Cheese	59.26	311.90
1332	Tasty Granite Cheese	14.47	952.09
1347	Tasty Granite Cheese	86.13	930.81
1372	Tasty Granite Cheese	90.82	785.66
1481	Tasty Granite Cheese	98.70	31.45
1510	Tasty Granite Cheese	80.86	344.05
1574	Tasty Granite Cheese	77.24	261.61
1232	Tasty Metal Ball	62.50	477.63
1254	Tasty Metal Ball	81.14	203.09
1278	Tasty Metal Ball	37.42	985.71
1316	Tasty Metal Ball	30.06	914.97
1328	Tasty Metal Ball	43.37	793.25
1346	Tasty Metal Ball	35.15	821.52
1398	Tasty Metal Ball	6.47	341.41
1410	Tasty Metal Ball	36.97	116.31
1465	Tasty Metal Ball	50.33	284.47
1472	Tasty Metal Ball	42.89	260.79
1478	Tasty Metal Ball	43.10	880.10
1493	Tasty Metal Ball	92.15	481.43
1502	Tasty Metal Ball	71.17	749.15
1542	Tasty Metal Ball	89.48	506.18
1571	Tasty Metal Ball	39.99	611.11
1220	Tasty Metal Hat	30.42	384.17
1296	Tasty Metal Hat	2.78	772.48
1335	Tasty Metal Hat	18.62	164.27
1345	Tasty Metal Hat	97.83	33.99
1372	Tasty Metal Hat	55.38	753.62
1384	Tasty Metal Hat	29.76	745.61
1412	Tasty Metal Hat	59.97	770.97
1433	Tasty Metal Hat	12.47	429.97
1446	Tasty Metal Hat	88.33	972.44
1482	Tasty Metal Hat	91.17	18.20
1495	Tasty Metal Hat	57.32	30.68
1269	Tasty Metal Keyboard	4.28	150.08
1300	Tasty Metal Keyboard	26.13	26.82
1325	Tasty Metal Keyboard	8.73	340.25
1347	Tasty Metal Keyboard	44.88	417.87
1446	Tasty Metal Keyboard	9.57	72.62
1449	Tasty Metal Keyboard	9.03	633.42
1463	Tasty Metal Keyboard	23.37	787.31
1494	Tasty Metal Keyboard	99.75	714.14
1509	Tasty Metal Keyboard	3.40	180.54
1524	Tasty Metal Keyboard	60.69	413.22
1551	Tasty Metal Keyboard	99.16	720.56
1564	Tasty Metal Keyboard	14.27	272.74
1575	Tasty Metal Keyboard	94.92	389.46
1586	Tasty Metal Keyboard	93.68	744.15
1215	Tasty Metal Pants	88.67	252.50
1221	Tasty Metal Pants	38.17	875.21
1247	Tasty Metal Pants	37.48	10.78
1259	Tasty Metal Pants	22.23	373.74
1327	Tasty Metal Pants	54.49	150.34
1412	Tasty Metal Pants	64.65	641.02
1459	Tasty Metal Pants	96.34	274.59
1487	Tasty Metal Pants	24.83	588.91
1549	Tasty Metal Pants	25.21	720.90
1278	Tasty Rubber Bike	63.52	786.11
1299	Tasty Rubber Bike	3.01	363.04
1304	Tasty Rubber Bike	11.17	239.25
1319	Tasty Rubber Bike	79.68	217.12
1355	Tasty Rubber Bike	51.84	382.54
1386	Tasty Rubber Bike	72.42	745.14
1400	Tasty Rubber Bike	1.55	319.50
1473	Tasty Rubber Bike	72.39	156.27
1495	Tasty Rubber Bike	65.81	623.20
1568	Tasty Rubber Bike	2.21	939.30
1238	Tasty Rubber Chips	71.98	935.71
1369	Tasty Rubber Chips	28.21	280.77
1375	Tasty Rubber Chips	27.17	563.45
1379	Tasty Rubber Chips	78.21	404.85
1405	Tasty Rubber Chips	39.85	579.86
1459	Tasty Rubber Chips	41.89	301.98
1469	Tasty Rubber Chips	78.80	168.59
1212	Tasty Soft Hat	78.81	97.99
1229	Tasty Soft Hat	31.48	866.89
1285	Tasty Soft Hat	35.34	916.49
1355	Tasty Soft Hat	20.72	438.07
1375	Tasty Soft Hat	91.73	802.43
1442	Tasty Soft Hat	98.22	566.04
1573	Tasty Soft Hat	2.70	891.72
1584	Tasty Soft Hat	88.37	676.61
1221	Tasty Soft Shoes	83.86	426.08
1293	Tasty Soft Shoes	26.60	43.27
1403	Tasty Soft Shoes	37.88	246.74
1479	Tasty Soft Shoes	37.40	256.74
1508	Tasty Soft Shoes	51.81	349.70
1379	Tasty Soft Tuna	2.96	263.11
1397	Tasty Soft Tuna	10.01	942.96
1440	Tasty Soft Tuna	23.08	191.26
1489	Tasty Soft Tuna	10.75	617.74
1520	Tasty Soft Tuna	24.00	531.85
1543	Tasty Soft Tuna	31.41	232.98
1552	Tasty Soft Tuna	72.42	158.42
1587	Tasty Soft Tuna	88.76	312.90
1608	Tasty Soft Tuna	63.17	105.94
1292	Tasty Steel Chips	22.81	758.41
1337	Tasty Steel Chips	3.17	390.28
1364	Tasty Steel Chips	97.60	963.95
1397	Tasty Steel Chips	37.00	835.85
1398	Tasty Steel Chips	95.83	418.86
1477	Tasty Steel Chips	22.65	492.42
1508	Tasty Steel Chips	34.86	983.03
1551	Tasty Steel Chips	94.15	708.46
1558	Tasty Steel Chips	68.30	639.34
1214	Tasty Steel Table	5.97	645.18
1227	Tasty Steel Table	94.66	425.60
1235	Tasty Steel Table	55.82	232.29
1291	Tasty Steel Table	48.79	407.63
1339	Tasty Steel Table	13.54	88.14
1351	Tasty Steel Table	34.79	475.13
1427	Tasty Steel Table	8.68	510.77
1541	Tasty Steel Table	30.96	65.68
1558	Tasty Steel Table	47.61	848.87
1567	Tasty Steel Table	96.77	625.84
1599	Tasty Steel Table	35.00	491.43
1276	Tasty Wooden Chips	48.93	591.77
1280	Tasty Wooden Chips	93.75	187.89
1339	Tasty Wooden Chips	77.09	917.95
1372	Tasty Wooden Chips	53.04	436.82
1377	Tasty Wooden Chips	94.68	746.52
1429	Tasty Wooden Chips	12.39	428.49
1539	Tasty Wooden Chips	80.88	900.59
1231	Tasty Wooden Gloves	25.98	138.32
1252	Tasty Wooden Gloves	44.51	88.22
1287	Tasty Wooden Gloves	6.44	543.20
1354	Tasty Wooden Gloves	75.65	376.37
1363	Tasty Wooden Gloves	58.01	122.14
1382	Tasty Wooden Gloves	43.61	472.24
1436	Tasty Wooden Gloves	15.68	846.77
1472	Tasty Wooden Gloves	70.43	292.94
1481	Tasty Wooden Gloves	9.68	934.43
1500	Tasty Wooden Gloves	92.23	717.93
1534	Tasty Wooden Gloves	90.82	469.22
1357	Unbranded Cotton Pizza	73.97	413.75
1421	Unbranded Cotton Pizza	93.50	181.17
1482	Unbranded Cotton Pizza	25.77	541.13
1526	Unbranded Cotton Pizza	86.17	83.51
1527	Unbranded Cotton Pizza	29.64	660.45
1532	Unbranded Cotton Pizza	96.17	756.22
1554	Unbranded Cotton Pizza	94.41	500.33
1605	Unbranded Cotton Pizza	68.20	765.32
1229	Unbranded Fresh Pizza	20.48	918.76
1236	Unbranded Fresh Pizza	34.37	310.95
1240	Unbranded Fresh Pizza	37.00	725.42
1262	Unbranded Fresh Pizza	44.22	761.04
1311	Unbranded Fresh Pizza	20.35	687.56
1316	Unbranded Fresh Pizza	56.77	331.46
1328	Unbranded Fresh Pizza	57.15	375.43
1340	Unbranded Fresh Pizza	21.77	145.86
1359	Unbranded Fresh Pizza	11.14	498.36
1374	Unbranded Fresh Pizza	8.32	982.58
1563	Unbranded Fresh Pizza	63.86	472.06
1292	Unbranded Frozen Keyboard	81.48	725.96
1309	Unbranded Frozen Keyboard	33.35	182.30
1364	Unbranded Frozen Keyboard	47.31	689.21
1411	Unbranded Frozen Keyboard	88.01	733.57
1519	Unbranded Frozen Keyboard	2.07	51.37
1524	Unbranded Frozen Keyboard	18.03	721.75
1531	Unbranded Frozen Keyboard	36.63	670.03
1563	Unbranded Frozen Keyboard	3.47	648.40
1569	Unbranded Frozen Keyboard	94.22	287.99
1578	Unbranded Frozen Keyboard	23.09	170.00
1586	Unbranded Frozen Keyboard	41.10	576.67
1261	Unbranded Granite Bike	19.12	71.46
1282	Unbranded Granite Bike	37.85	263.61
1295	Unbranded Granite Bike	97.37	820.62
1356	Unbranded Granite Bike	5.89	590.88
1398	Unbranded Granite Bike	90.01	40.78
1520	Unbranded Granite Bike	80.24	270.55
1522	Unbranded Granite Bike	39.41	908.77
1551	Unbranded Granite Bike	18.58	722.07
1592	Unbranded Granite Bike	60.64	574.34
1609	Unbranded Granite Bike	16.90	763.98
1225	Unbranded Metal Fish	58.89	249.43
1324	Unbranded Metal Fish	87.41	21.98
1402	Unbranded Metal Fish	63.80	71.91
1407	Unbranded Metal Fish	54.61	188.82
1464	Unbranded Metal Fish	64.90	188.88
1218	Unbranded Metal Fish 1	30.36	471.32
1220	Unbranded Metal Fish 1	61.54	20.19
1323	Unbranded Metal Fish 1	85.55	145.88
1353	Unbranded Metal Fish 1	67.27	656.42
1454	Unbranded Metal Fish 1	64.03	367.96
1567	Unbranded Metal Fish 1	19.16	813.83
1571	Unbranded Metal Fish 1	96.78	94.45
1585	Unbranded Metal Fish 1	23.08	57.84
1223	Unbranded Metal Hat	26.86	610.61
1395	Unbranded Metal Hat	96.82	656.10
1478	Unbranded Metal Hat	55.69	525.99
1509	Unbranded Metal Hat	87.46	847.61
1523	Unbranded Metal Hat	76.43	659.32
1271	Unbranded Steel Chair	47.97	17.52
1283	Unbranded Steel Chair	58.08	558.62
1348	Unbranded Steel Chair	54.64	286.08
1393	Unbranded Steel Chair	42.02	453.80
1469	Unbranded Steel Chair	7.21	562.87
1475	Unbranded Steel Chair	21.32	390.13
1524	Unbranded Steel Chair	77.39	148.17
1525	Unbranded Steel Chair	23.20	713.63
1543	Unbranded Steel Chair	47.06	616.06
1606	Unbranded Steel Chair	54.23	711.46
1619	Adjustable Office Chair	10.00	150.00
1619	Wireless Keyboard	20.00	50.00
1620	Noise-Canceling Headphones	15.00	100.00
1620	Wireless Keyboard	10.00	55.00
1621	Adjustable Office Chair	5.00	145.00
1628	Steel Beams	5.00	500.00
1629	Marble Slabs	10.00	1200.00
1502	Cement M500	5.00	350.00
1502	Ceramic Tiles	9.00	150.00
1630	Ceramic Tiles	9.00	150.00
1630	Cement M500	10.00	300.00
1631	Cement M500	10.00	300.00
1632	Cement M500	10.00	400.00
1633	Cement M500	10.00	300.00
\.


--
-- TOC entry 4946 (class 0 OID 16532)
-- Dependencies: 221
-- Data for Name: product; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product (product_name, units, last_price) FROM stdin;
Handcrafted Cotton Chicken	pcs	218.84
Handcrafted Fresh Mouse	m	955.72
Handcrafted Frozen Pants	kg	536.94
Handcrafted Granite Shirt	m	94.89
Handcrafted Metal Keyboard	pcs	933.99
Handcrafted Plastic Hat	m	510.39
Handcrafted Plastic Hat 1	kg	865.98
Handcrafted Soft Chair	kg	491.20
Handcrafted Soft Fish	kg	539.49
Handcrafted Soft Pants	kg	172.36
Handcrafted Wooden Pizza	kg	70.58
Handmade Cotton Chips	m	543.24
Handmade Fresh Chair	pcs	484.80
Handmade Fresh Chicken	kg	114.24
Handmade Fresh Tuna	m	183.62
Handmade Granite Pants	m	979.55
Handmade Plastic Bike	pcs	973.68
Handmade Rubber Chair	kg	812.37
Handmade Rubber Shirt	kg	483.47
Handmade Soft Towels	kg	706.55
Handmade Wooden Bacon	m	327.41
Incredible Concrete Chicken	pcs	658.24
Incredible Cotton Ball	kg	727.78
Incredible Fresh Chips	kg	970.37
Incredible Granite Car	kg	836.35
Incredible Metal Bike	pcs	934.32
Incredible Metal Fish	kg	237.67
Incredible Metal Table	kg	313.80
Incredible Metal Tuna	pcs	85.11
Incredible Rubber Bacon	kg	618.64
Incredible Rubber Chair	pcs	162.73
Incredible Rubber Shoes	kg	770.33
Incredible Steel Cheese	kg	652.40
Incredible Steel Sausages	m	833.94
Incredible Wooden Computer	pcs	597.99
Incredible Wooden Soap	m	78.51
Intelligent Cotton Bacon	kg	155.45
Intelligent Fresh Mouse	m	977.86
Intelligent Fresh Pizza	m	816.51
Intelligent Granite Chips	pcs	612.35
Intelligent Granite Sausages	m	156.02
Intelligent Metal Chicken	m	470.42
Intelligent Plastic Fish	pcs	427.14
Intelligent Plastic Pizza	kg	247.18
Intelligent Rubber Chair	m	222.66
Intelligent Rubber Pizza	m	997.71
Intelligent Soft Hat	kg	260.96
Intelligent Soft Pizza	pcs	161.00
Intelligent Wooden Salad	kg	191.84
Licensed Concrete Shoes	pcs	385.42
Licensed Cotton Bacon	kg	197.70
Licensed Cotton Ball	pcs	854.22
Licensed Fresh Pizza	pcs	374.81
Licensed Frozen Chair	kg	783.40
Licensed Frozen Computer	pcs	524.77
Licensed Frozen Mouse	m	897.18
Licensed Granite Keyboard	m	846.13
Licensed Plastic Bacon	kg	266.84
Licensed Plastic Chicken	kg	62.54
Licensed Plastic Sausages	m	213.08
Licensed Plastic Shirt	kg	580.45
Licensed Rubber Mouse	pcs	67.51
Licensed Soft Computer	pcs	419.81
Licensed Soft Keyboard	pcs	627.82
Licensed Steel Bacon	m	750.92
Licensed Steel Fish	kg	863.27
Licensed Steel Shoes	pcs	98.07
Licensed Wooden Cheese	pcs	637.43
Licensed Wooden Sausages	m	429.13
Licensed Wooden Towels	pcs	750.07
Practical Concrete Salad	pcs	37.20
Practical Cotton Gloves	m	469.73
Practical Cotton Keyboard	m	496.28
Practical Fresh Chips	pcs	684.14
Practical Fresh Keyboard	m	562.93
Practical Plastic Mouse	pcs	195.17
Practical Plastic Shirt	m	969.39
Practical Soft Bacon	pcs	371.00
Practical Soft Shirt	pcs	945.16
Refined Concrete Pants	m	704.39
Refined Cotton Soap	kg	362.68
Refined Fresh Chair	pcs	79.63
Refined Fresh Chips	kg	929.91
Refined Rubber Pants	kg	244.29
Refined Steel Fish	m	174.62
Refined Steel Mouse	pcs	329.09
Refined Wooden Car	pcs	615.19
Refined Wooden Table	pcs	868.94
Rustic Concrete Chair	kg	964.79
Rustic Concrete Shirt	m	750.24
Rustic Frozen Bacon	m	185.61
Rustic Frozen Ball	pcs	421.24
Rustic Frozen Chair	pcs	938.47
Rustic Granite Cheese	m	598.65
Rustic Metal Chips	kg	58.35
Rustic Metal Sausages	pcs	808.31
Rustic Rubber Fish	kg	291.86
Rustic Rubber Shirt	m	208.36
Rustic Soft Chips	pcs	242.66
Rustic Wooden Hat	pcs	259.56
Sleek Cotton Cheese	m	189.21
Sleek Cotton Soap	pcs	650.82
Sleek Fresh Bacon	kg	523.12
Sleek Fresh Keyboard	pcs	29.94
Sleek Frozen Chicken	m	206.42
Sleek Granite Car	pcs	879.52
Sleek Granite Fish	kg	377.61
Sleek Granite Tuna	kg	691.55
Sleek Metal Soap	m	404.23
Small Cotton Salad	kg	327.47
Small Fresh Car	kg	125.01
Small Frozen Bike	kg	559.37
Small Plastic Bike	kg	414.69
Small Plastic Cheese	kg	979.18
Small Soft Gloves	m	29.84
Small Soft Pizza	m	111.14
Tasty Concrete Shoes	pcs	497.25
Tasty Soft Hat	m	779.01
Tasty Concrete Tuna	pcs	318.09
Tasty Cotton Keyboard	pcs	222.25
Tasty Fresh Computer	m	711.27
Tasty Fresh Salad	pcs	533.54
Tasty Granite Cheese	pcs	846.18
Tasty Metal Ball	m	477.63
Tasty Metal Hat	pcs	384.17
Tasty Metal Keyboard	kg	150.08
Tasty Metal Pants	pcs	252.50
Tasty Rubber Bike	kg	786.11
Awesome Cotton Gloves	kg	249.16
Awesome Cotton Sausages	kg	594.56
Awesome Fresh Chicken	m	212.32
Awesome Fresh Chips	m	565.33
Awesome Metal Hat	kg	171.16
Awesome Metal Shoes	kg	116.32
Awesome Plastic Tuna	pcs	259.91
Awesome Rubber Soap	pcs	181.73
Ergonomic Fresh Mouse	m	77.28
Ergonomic Frozen Chips	m	224.03
Ergonomic Granite Cheese	kg	749.82
Ergonomic Metal Cheese	pcs	234.46
Ergonomic Plastic Gloves	pcs	635.13
Ergonomic Rubber Sausages	kg	148.97
Ergonomic Soft Bacon	kg	199.98
Ergonomic Steel Bike	kg	399.38
Ergonomic Wooden Table	kg	683.89
Fantastic Concrete Fish	kg	153.99
Fantastic Fresh Chips	kg	233.72
Fantastic Fresh Salad	kg	694.98
Fantastic Frozen Chicken	kg	860.89
Fantastic Granite Chips	m	232.99
Fantastic Granite Pizza	kg	748.25
Fantastic Granite Tuna	m	759.19
Fantastic Rubber Keyboard	pcs	625.23
Fantastic Soft Bike	pcs	781.32
Fantastic Steel Chicken	pcs	286.75
Generic Concrete Shirt	m	977.00
Generic Fresh Car	pcs	651.12
Generic Fresh Chair	pcs	361.20
Generic Fresh Keyboard	m	284.92
Generic Granite Bacon	pcs	852.65
Generic Plastic Chair	kg	571.72
Generic Rubber Keyboard	m	931.69
Generic Rubber Salad	m	115.89
Generic Rubber Soap	m	37.14
Generic Soft Bike	m	294.31
Generic Soft Salad	m	974.39
Generic Steel Keyboard	kg	565.67
Generic Wooden Gloves	pcs	688.47
Generic Wooden Towels	pcs	169.05
Gorgeous Fresh Chicken	kg	763.44
Gorgeous Fresh Fish	pcs	844.55
Gorgeous Rubber Computer	m	20.63
Gorgeous Soft Car	kg	210.11
Gorgeous Soft Cheese	kg	830.45
Gorgeous Soft Chicken	pcs	216.88
Gorgeous Soft Pants	m	204.48
Gorgeous Soft Sausages	m	775.80
Gorgeous Soft Shoes	pcs	227.97
Gorgeous Soft Towels	pcs	785.65
Gorgeous Steel Computer	kg	285.41
Gorgeous Wooden Bike	m	372.28
Gorgeous Wooden Chicken	m	263.10
Handcrafted Concrete Fish	m	356.98
Practical Metal Hat	pcs	976.40
Handcrafted Concrete Pizza	kg	208.56
Adjustable Office Chair	pcs	120.00
Wireless Keyboard	pcs	45.00
Noise-Canceling Headphones	pcs	200.00
LED Desk Lamp	pcs	30.00
Ceramic Tiles	m2	150.00
Steel Beams	m	500.00
Marble Slabs	m2	1200.00
Cement M500	ton	300.00
Tasty Rubber Chips	pcs	935.71
Tasty Soft Shoes	kg	426.08
Tasty Soft Tuna	m	263.11
Tasty Steel Chips	m	758.41
Tasty Steel Table	kg	645.18
Tasty Wooden Chips	kg	591.77
Tasty Wooden Gloves	m	138.32
Unbranded Cotton Pizza	kg	413.75
Unbranded Fresh Pizza	pcs	918.76
Unbranded Frozen Keyboard	m	725.96
Unbranded Granite Bike	kg	71.46
Unbranded Metal Fish	m	249.43
Unbranded Metal Fish 1	kg	471.32
Unbranded Metal Hat	pcs	610.61
Unbranded Steel Chair	m	17.52
\.


--
-- TOC entry 4944 (class 0 OID 16514)
-- Dependencies: 219
-- Data for Name: storage; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.storage (storage_id, street_name, house_number, city, region, postal_code) FROM stdin;
1502	Strosin Center	003	Lake Orintown	New Hampshire	192
1503	Mabel Knoll	110	Joliestad	Wisconsin	022
1504	Moen Tunnel	801	Katelyntown	Kansas	677
1505	Gunnar Fork	164	Runolfsdottirshire	Washington	383
1506	Seth Hills	657	West Hanna	Hawaii	702
1507	Alanis Park	048	Andreannefort	Idaho	007
1508	Pfeffer Pines	744	Janieport	Maryland	271
1509	Mills Creek	073	New Diana	Florida	127
1510	D'Amore Street	829	Weldonberg	Utah	787
1511	Weissnat Isle	147	Faheymouth	Massachusetts	967
1512	Fahey Mews	313	New Camille	Nevada	482
1513	Runolfsson Plain	223	Lake Holly	Michigan	290
1514	Aryanna Inlet	838	Lake Feltontown	Missouri	864
1515	Dawson Vista	608	Stantonfort	Arizona	181
1516	Beatty Crest	151	North Percyburgh	Louisiana	409
1517	Gleason Viaduct	571	New Jordanefort	Montana	890
1518	Hodkiewicz Brooks	502	North Santoston	Utah	106
1519	Aufderhar Field	660	Port Amberton	Wisconsin	600
1520	Greenholt Causeway	773	Shanahanview	Indiana	966
1521	Ortiz Neck	687	Juniusland	Oklahoma	774
1522	Gerard Spur	335	North Caramouth	Washington	310
1523	Aubrey Isle	830	Abernathyhaven	Hawaii	315
1524	Stroman Trail	899	East Eudoramouth	Idaho	245
1525	Carmela Points	437	West Rahsaanchester	North Carolina	356
1526	Nathanial Street	362	Bartellport	West Virginia	642
1527	Brett Plain	052	Port Roslyn	Louisiana	886
1528	Gulgowski Trail	335	Russelport	Michigan	933
1529	Blanda Rest	580	Lake Pablo	Kansas	544
1530	Maybell Burgs	238	Marshallchester	Mississippi	307
1531	Boehm Inlet	973	Port Kristofferland	Virginia	220
1532	Emilia Spur	159	West Gilbertobury	Minnesota	302
1533	Frances Pine	506	North Mireyaville	Nebraska	341
1534	Pouros Drive	533	Port Yadirafort	North Carolina	123
1535	Jamel Islands	043	West Pabloburgh	Kansas	551
1536	Joana Viaduct	914	Lake Ayana	Montana	398
1537	Bernice Ridge	668	South Tateport	Alabama	961
1538	Cartwright River	696	Jacyntheton	Delaware	829
1539	Mozelle Forest	935	Jedidiahchester	Nevada	461
1540	Spinka Divide	142	Port Filiberto	Connecticut	666
1541	Jenkins Trace	837	Kaitlinshire	Tennessee	663
1542	Casimir Pine	516	Roobbury	Tennessee	495
1543	Leilani Bridge	701	Einochester	Wisconsin	131
1544	Gusikowski Ramp	077	Rozellafurt	Wyoming	005
1545	Alek Glen	378	Geraldineland	West Virginia	074
1546	Kirlin Crescent	289	McCluremouth	Virginia	735
1547	Lynch Bridge	495	Llewellynbury	Hawaii	000
1548	Spinka Crescent	337	East Jeremy	West Virginia	259
1549	Corwin Flat	584	South Bradlyport	Michigan	414
1550	Marta Ports	694	West Camila	Indiana	709
1551	Fahey Summit	649	West Noah	Maryland	534
1552	Miracle Passage	882	East Wellington	Ohio	573
1553	Shayne Radial	784	North Aleen	Maine	748
1554	Adella Stravenue	193	East Henriette	Arizona	502
1555	Garnet Road	602	Harveyberg	New Hampshire	371
1556	McKenzie Courts	140	East Rodolfoville	Mississippi	157
1557	Domenica Locks	495	South Gregorio	Nebraska	708
1558	Smitham Fork	829	West Pansyfurt	Virginia	546
1559	Raina Plains	415	Lorenzofort	California	066
1560	Funk Heights	416	Dejonhaven	Texas	746
1561	Ziemann Rapid	071	South Esmeralda	Texas	924
1562	Brook Rapid	288	West Oraland	New York	243
1563	Gaston Via	663	Port Elainaville	Virginia	215
1564	Vivian Spring	651	New Murray	Nevada	009
1565	Dewitt Lodge	621	Kavonmouth	North Carolina	513
1566	Kaleigh Drive	347	South Pearline	Pennsylvania	597
1567	Derick Branch	368	East Maximobury	Delaware	511
1568	Hodkiewicz Fall	915	Nestorfurt	Rhode Island	331
1569	Matilde Skyway	565	Katlynnberg	Tennessee	264
1570	Hintz Port	211	Port Jerrell	South Carolina	886
1571	Deckow Oval	607	Jermaineland	North Dakota	879
1572	Conn Oval	901	Nitzscheville	Oklahoma	360
1573	Ernser Vista	952	Wilmamouth	Connecticut	362
1574	Wyman Alley	721	Kuhlmanview	Nevada	471
1575	Williamson Street	643	Makennaland	Maryland	480
1576	Toy Spur	023	Lelahland	Washington	646
1577	Rachael Unions	552	Halvorsonbury	Nevada	176
1578	Mazie Stream	521	Bradtkeburgh	Utah	706
1579	Samara Unions	062	New Anthonyside	Delaware	282
1580	Klocko Vista	910	Ezekielland	New Jersey	182
1581	Cornell Point	044	Gloverhaven	Washington	652
1582	Haag Streets	541	Blockchester	Texas	326
1583	Thiel Run	147	North Modesto	Indiana	849
1584	Blaze Causeway	440	Rolfsonmouth	West Virginia	232
1585	Milford Keys	937	South Ubaldo	Ohio	601
1586	Torey Bridge	070	Jerroldfort	Kansas	309
1587	Van Flats	849	Celiaton	Kansas	039
1588	Nikolaus Oval	133	West Maybell	Michigan	951
1589	Daniel Haven	342	North Lucy	Nebraska	413
1590	Mable Crescent	401	South Giovani	Idaho	371
1591	Alice Isle	367	Jovannyside	Virginia	799
1592	Beryl Plain	027	Thoraland	Maryland	756
1593	Kohler Dale	657	East Liza	Tennessee	570
1594	Hilll Plains	861	Swaniawskimouth	Missouri	058
1595	Hodkiewicz Isle	354	Joelfurt	Kentucky	314
1596	Lowe Neck	110	South Maximilliabury	Oklahoma	266
1597	Marquardt Port	272	Port Jonathonshire	North Dakota	649
1598	Kirlin Crest	709	Weimannside	Florida	169
1599	Abner Isle	730	Maceyburgh	Alabama	214
1600	Shanahan Orchard	359	West Dane	New York	263
1601	Shawn Flat	348	East Maggieburgh	Oregon	030
1602	Friesen Underpass	264	Marciaburgh	New York	910
1603	Tod Path	009	Port Ephraim	Wyoming	235
1604	Enola Points	131	North Hattie	West Virginia	237
1605	Dandre Mountain	957	Gutkowskiport	Kansas	035
1606	Donnelly Spurs	016	West Orval	Florida	296
1607	Miller Fields	924	Cortneyville	Kansas	005
1608	Gleichner Valleys	047	West Katlyn	Wisconsin	799
1609	Kylie Fields	305	Runolfssonport	Tennessee	236
1610	Ferry Forks	018	Lehnerside	Delaware	725
1611	Wolf Radial	586	South Otha	Tennessee	497
1612	Edwardo Vista	636	Port Brycen	Pennsylvania	844
1613	Okuneva Causeway	822	Garrickborough	Arizona	442
1614	Schmitt Mill	865	Ritamouth	New Jersey	761
1615	Cierra Alley	764	Koelpinfurt	Texas	058
1616	Williamson Underpass	915	New Myah	Connecticut	874
1617	Turner Burgs	243	Port Danial	Mississippi	203
1618	Raynor Rest	959	North Norene	Idaho	687
1619	Jarod Loaf	190	Mullerview	Kansas	203
1620	Jettie Locks	523	Leannonburgh	Washington	079
1621	Laila Terrace	729	Madelynberg	New Jersey	300
1622	White Ports	611	West Keyshawn	Nebraska	505
1623	Haley Spring	366	Melvinaburgh	Alabama	059
1624	Haven Court	381	South Tobinville	Pennsylvania	865
1625	Heathcote Greens	469	Pfefferland	Wisconsin	573
1626	Stanton Dam	695	Gianniville	Wyoming	276
1627	Nolan Pine	148	Lake Santiagomouth	Illinois	960
1628	Glenda Manors	119	Cristburgh	Vermont	637
1629	Rashawn Bypass	117	Justenchester	Georgia	188
1630	Abshire Mountain	632	New Julian	New York	824
1631	Berge Crossroad	553	Bricestad	New Jersey	807
1632	Claudia Trafficway	586	Lake Alexie	Colorado	099
1633	Jimmie Field	601	West Belleport	Kansas	773
1634	Scottie Shoals	530	Blockchester	Georgia	220
1635	Jena Harbor	812	Rippinton	Alaska	059
1636	Abner Parkway	368	North Armandoburgh	Maine	230
1637	Hilll Wells	623	Savannahberg	Vermont	411
1638	Alek Rapid	206	New Mattiehaven	Hawaii	272
1639	Marks Expressway	004	Lake Oscarside	Massachusetts	316
1640	Deonte Hill	428	North Vickiemouth	Alaska	538
1641	Brittany Junctions	054	Greenholttown	Iowa	184
1642	Dicki Ferry	677	Zanefurt	Rhode Island	736
1643	Freda Streets	681	East Deven	North Carolina	827
1644	Torphy Shoal	768	Theresiastad	Arizona	994
1645	Glover Plaza	570	Jenkinsland	Montana	371
1646	Bartoletti Trail	425	Alessandroborough	Maine	653
1647	Gunnar Stream	401	South Friedrich	Michigan	172
1648	Hyatt Streets	035	Aufderharton	Virginia	059
1649	Yundt Bypass	064	New Rozella	New Jersey	768
1650	Watsica Trace	579	Nienowstad	Maine	126
1651	Elian Mission	679	Paucekbury	Indiana	274
1652	Khalid Camp	892	East Maiyashire	Ohio	974
1653	Otto Burg	235	Carrollborough	South Dakota	469
1654	Kieran Port	911	Port Ardenborough	Wisconsin	792
1655	Princess Road	165	East Lenny	Massachusetts	772
1656	Dena Fort	381	Stammfurt	Colorado	543
1657	Ullrich Squares	358	Lake Nayelifort	North Carolina	367
1658	Lynch Keys	565	South Armandobury	West Virginia	407
1659	Feest Summit	165	Moenbury	Massachusetts	047
1660	Kyle Orchard	131	Omatown	Montana	522
1661	Rath Squares	579	Schoenmouth	Kansas	149
1662	Kuvalis Road	391	Champlinport	Hawaii	298
1663	Jarrod Creek	557	McGlynnstad	Mississippi	307
1664	Gavin Neck	184	Monahanville	New Hampshire	977
1665	Melyssa Station	253	Danielland	Kentucky	927
1666	Rusty Grove	911	South Nicholasville	Ohio	524
1667	Heath Lodge	882	Christinaberg	Iowa	928
1668	Claire Walks	132	Port Bernard	New Jersey	550
1669	Gustave Ways	474	Tessieton	South Carolina	588
1670	Towne Road	764	Sarahfurt	Mississippi	916
1671	Cronin Inlet	942	New Isaias	New Hampshire	275
1672	Windler Radial	897	Leonelmouth	Vermont	985
1673	Lindsay Field	616	Lake Cooper	Mississippi	947
1674	Kira Hill	275	Kertzmannchester	Oklahoma	505
1675	Evert Springs	478	East Greyson	Washington	565
1676	Parker Loaf	776	Littelton	South Carolina	599
1677	Mills Center	630	Lake Jacquelynfurt	Kentucky	345
1678	Ahmad Plaza	301	Weissnatfort	Utah	676
1679	Kali Highway	215	New Lolita	New York	446
1680	Rubie Spurs	968	Balistrerifurt	Hawaii	757
1681	Tillman Locks	993	Kunzeberg	Maine	944
1682	Maryjane Run	241	Lowehaven	Hawaii	677
1683	Pollich Summit	380	Port Simone	Minnesota	746
1684	Naomie Flat	521	South Candido	Mississippi	194
1685	Otilia Mills	152	Framimouth	Massachusetts	553
1686	Robel Spur	128	Douglasview	Connecticut	865
1687	Ondricka Mall	973	Monahanfurt	Alaska	638
1688	Jimmy Extensions	955	North Alyson	Michigan	893
1689	Hauck Falls	719	South Chazland	Arizona	955
1690	Lenna Causeway	746	New Sylvan	Oklahoma	625
1691	Elva Summit	996	North Ned	Utah	938
1692	Kovacek Way	746	Aprilside	Iowa	570
1693	Sarah Fall	326	Wildermanfort	Hawaii	268
1694	Simone Loaf	224	Lake Meghan	Indiana	136
1695	Goyette Forest	786	South Victorside	Oklahoma	286
1696	Welch Pike	604	East Alivia	West Virginia	230
1697	Aimee Garden	375	North Malvinaton	Alaska	416
1698	Keyon Stream	027	Osbaldostad	Arizona	716
1699	Deckow Spring	545	Port Arnold	Louisiana	711
1700	Wilderman Manor	956	New Carmelo	Illinois	667
1701	Reichert Road	945	Ewaldhaven	Georgia	414
1702	Upton Mill	608	Gibsonshire	Kentucky	553
1703	Wyatt Crossing	187	Port Jerad	Mississippi	783
1704	Adah Skyway	488	Julesborough	Nevada	098
1705	Reagan Terrace	941	East Brent	California	080
1706	Gibson Dale	219	Edmundbury	Texas	900
1707	Spencer Spurs	821	Johnsonburgh	Mississippi	461
1708	Vada Islands	811	Mireilleland	Utah	824
1709	Skyla Unions	137	South Dellhaven	Alaska	208
1710	Wilkinson Loop	982	West Damian	Hawaii	260
1711	Connie Corner	519	Hellerview	Michigan	658
1712	Herman Dale	089	Trantowborough	Wisconsin	500
1713	Porter Green	997	Grahamstad	Alaska	186
1714	Arnold Islands	592	Lake Wilmertown	Illinois	878
1715	Cronin Manor	491	Giovaniton	Colorado	135
1716	Mabelle Cape	248	Millsfort	Hawaii	584
1717	Taurean Glens	608	Tobinmouth	South Dakota	371
1718	Bogan Harbors	122	East Tyreek	Michigan	582
1719	Dickinson Knoll	644	East Imelda	Hawaii	872
1720	Roberts Trail	899	Port Lemuelburgh	Minnesota	093
1721	Marques Vista	195	Cleoraland	Nebraska	798
1722	Nienow Lodge	867	Verlatown	North Dakota	088
1723	Bednar Cliff	898	Kennyhaven	South Dakota	436
1724	Cary Ports	344	Creolachester	South Carolina	536
1725	Goodwin Islands	045	South Mavis	Hawaii	786
1726	Walsh Drives	300	North Alf	Maine	966
1727	Huels Lodge	802	Julianneview	Georgia	318
1728	Cole Knoll	981	Quigleytown	New Mexico	826
1729	Bahringer Locks	577	Ryleyton	Idaho	846
1730	Turner Flats	267	Port Jamaalberg	Pennsylvania	639
1731	Tillman Vista	979	Sydneefurt	New York	754
1732	Krajcik Lane	812	Hansenberg	Kansas	040
1733	Domenick Bridge	988	North Devynberg	Rhode Island	363
1734	Walker Vista	053	Lavadastad	California	602
1735	Enoch Trace	618	Lake Coralie	Nevada	847
1736	Turcotte Mews	716	Haagbury	Vermont	337
1737	Pagac Forks	923	North Michale	Florida	494
1738	Heathcote Loaf	139	Handbury	Indiana	706
1739	Gulgowski Burgs	169	Rogahnport	South Dakota	341
1740	Beier Points	008	Randalborough	Utah	605
1741	Senger Mount	335	South Turner	Montana	217
1742	Colin Turnpike	902	West Frances	North Carolina	816
1743	Hirthe Ways	337	North Santosshire	Nebraska	418
1744	Breana Course	696	Bechtelarside	Indiana	080
1745	Neoma Square	270	Wilkinsonchester	Michigan	408
1746	Howard Haven	247	Wisokyland	Vermont	853
1747	Thompson Lodge	665	North Raestad	Louisiana	118
1748	Porter Drive	618	Walshside	Louisiana	719
1749	Aurelia Extensions	471	Mosciskifort	Maryland	362
1750	Lou Garden	422	Kurtburgh	Indiana	857
1751	Douglas Valley	121	West Ivafurt	Delaware	793
1752	Hyatt Field	222	South Antonetta	South Carolina	319
1753	Hyatt Lights	133	Port Jaylinland	North Carolina	283
1754	Kilback Shores	772	Sonnyborough	Kentucky	212
1755	Green Squares	288	Gregoriohaven	Vermont	934
1756	Danielle Fields	424	Marianaborough	Utah	909
1757	Fritsch Manors	863	East Geoffrey	New York	805
1758	Andrew Meadow	936	Rosalindtown	Arkansas	369
1759	Bart Mountains	126	Wunschborough	Washington	030
1760	Hammes Skyway	317	East Amelyland	Mississippi	255
1761	Ankunding Groves	761	Swaniawskifurt	New York	936
1762	Caterina Row	815	Camillaborough	Iowa	390
1763	Leannon Garden	719	Gayshire	New York	836
1764	Kirsten Brook	899	New Mathiasburgh	Alabama	130
1765	Raoul Lake	508	Raynorstad	Georgia	914
1766	Zola Court	851	Imeldamouth	New Jersey	552
1767	Reichel Corner	778	Stacyville	Wyoming	167
1768	Strosin Brooks	740	Beierport	Arizona	260
1769	German Extension	415	Leonorbury	Rhode Island	598
1770	Collier Village	758	North Stanley	Alabama	935
1771	Alexandrea Trafficway	867	Hesselbury	Virginia	139
1772	Lemuel Crossing	444	South Clara	Ohio	747
1773	Camren Forks	753	South Tyresestad	Texas	014
1774	Ziemann Mount	591	Port Lurline	New York	700
1775	Mollie River	217	Destinyville	Texas	234
1776	Witting Overpass	508	North Lizethborough	Ohio	601
1777	Hammes Light	740	Pfeffershire	North Carolina	348
1778	Gaetano Freeway	372	Emilianoshire	North Dakota	700
1779	Deshaun Union	404	West Keventown	Utah	252
1780	Nayeli Union	248	Okunevaside	Indiana	990
1781	Fannie Bypass	375	North Renemouth	Arkansas	889
1782	Feil Corners	991	Norwoodburgh	Vermont	019
1783	Virginie Glens	973	West Stacy	Alabama	809
1784	Koss Pine	385	North Brownland	Alabama	099
1785	Rohan Shores	559	Auerville	Kentucky	085
1786	Ferry Points	703	Yundtburgh	Maryland	581
1787	Toy Crescent	833	Bradenport	Louisiana	697
1788	Izabella Valley	219	North Ariel	California	283
1789	Little Plains	632	South Abdiel	Maine	741
1790	Jasper Village	192	Cyrusmouth	Nebraska	309
1791	Mraz Flats	534	Port Mackenzie	Hawaii	214
1792	Nikolaus Bypass	500	New Brenda	Maine	182
1793	Braun Land	065	Lake Abbey	Michigan	755
1794	Schroeder Mount	167	Watsicamouth	South Dakota	932
1795	Albin Mission	735	Lake Lanefort	Idaho	018
1796	Bahringer Pass	042	East Nathan	Wyoming	408
1797	Raina Streets	233	East Robyn	Washington	805
1798	Vincenza Greens	813	Maudebury	Massachusetts	420
1799	Janie Meadows	117	Venafort	New York	724
1800	Weber Well	199	Dorischester	Indiana	804
1801	Fiona Pine	764	Kleinview	West Virginia	857
1802	Allison Trail	616	Port Kyler	Vermont	748
1803	Titus Locks	030	Koelpinport	New Mexico	445
1804	Howe Course	936	Shanahanbury	Minnesota	361
1805	Monahan Estate	903	Ernestoland	Louisiana	082
1806	Aiyana Place	750	South Jade	Arkansas	763
1807	Tyra Vista	119	West Justusstad	Mississippi	359
1808	Glover Fort	693	Binsstad	Montana	306
1809	Crawford Forge	265	Turnerland	Ohio	470
1810	Willie Trail	889	West Mateoton	Wisconsin	728
1811	Nienow Junction	579	Franciscomouth	Michigan	763
1812	Lisette Villages	538	Ilianaview	Pennsylvania	025
1813	Beer Island	239	D'Amoremouth	Massachusetts	874
1814	Andres Flats	236	New Kamron	Nebraska	561
1815	Spinka Fords	533	West Aracelyfurt	Washington	249
1816	Goyette Views	690	Aliaborough	Iowa	966
1817	Terry Lane	469	Lueilwitzmouth	Michigan	308
1818	Heller Shoal	091	Haagland	Idaho	336
1819	Bergnaum Spurs	321	North Brady	California	327
1820	Cremin Ways	267	North Jamarstad	Idaho	279
1821	Schinner Bypass	754	Sadyefort	Arkansas	882
1822	Clint Hill	186	Wizatown	Washington	944
1823	Roob Walk	968	South Inestown	California	756
1824	Genoveva Groves	821	New Cletaport	Hawaii	628
1825	Anthony Mountain	378	Coraliemouth	Louisiana	677
1826	McClure Courts	421	North Sigurdmouth	Florida	281
1827	Flavie Lock	301	Homenickport	Michigan	634
1828	Pfannerstill Ville	161	Keeblerfort	Ohio	506
1829	Veum Lock	626	East Rosalind	Tennessee	280
1830	Bergstrom Ways	152	Bodeborough	North Carolina	430
1831	Kiarra Prairie	136	South Natalie	Oklahoma	745
1832	Parker Greens	093	Jadenfort	West Virginia	545
1833	Gunnar Summit	428	Ziemeland	Nebraska	389
1834	Flossie Crossing	639	North Earl	South Carolina	576
1835	Adrianna Ports	494	Demondton	Indiana	319
1836	Piper Station	301	Brownland	Louisiana	654
1837	Eliane Plaza	936	Powlowskiborough	Missouri	977
1838	Johnny Crescent	950	Cydneyton	Wyoming	887
1839	Deion Radial	683	Oberbrunnerchester	South Dakota	302
1840	Andy Islands	801	Violetteview	Louisiana	957
1841	Heaney Estates	170	Schuppestad	North Dakota	813
1842	Feil Street	919	New Clemmie	Georgia	371
1843	Alicia Way	164	Maudieside	Tennessee	909
1844	Rohan Street	943	Lebsackport	Tennessee	522
1845	Garnet Streets	928	Zackarybury	Arizona	757
1846	Jones Junction	589	Maymieview	Nevada	545
1847	Shaina Islands	200	Amiyaton	Rhode Island	476
1848	Schultz Isle	333	Rogahnbury	Arizona	447
1849	Pagac Overpass	017	Smithchester	North Carolina	296
1850	Lynch Gardens	676	West Stanford	Alaska	288
1851	Charlene Orchard	146	Hayesfort	Vermont	354
1852	Zackary Bridge	899	Port Gertrudeberg	Louisiana	511
1853	Melissa Ramp	833	Heidenreichside	Kansas	120
1854	Rohan Mission	927	Monroemouth	Ohio	063
1855	Stracke Court	653	Sharonbury	Colorado	648
1856	Eusebio Shores	756	Port Jesse	Virginia	744
1857	D'Amore Brooks	585	North Jamey	Kansas	836
1858	Thad Station	310	Jacobibury	South Carolina	945
1859	Carroll Hills	437	Streichshire	North Dakota	759
1860	Hermann Creek	803	New Reggieland	New York	234
1861	Bartell Walk	274	Pourostown	Connecticut	724
1862	Joshua Vista	273	New Stuart	New York	459
1863	Okey Motorway	733	North Jaime	Tennessee	618
1864	Mariano Plain	295	Lake May	Virginia	901
1865	Upton Courts	123	Swiftstad	Kentucky	069
1866	Sawayn Alley	896	East Mia	Oklahoma	390
1867	Nitzsche Cape	103	Caleighfort	Georgia	575
1868	Hazle Stream	854	Laurianneville	Nebraska	730
1869	Estella Stravenue	841	Cleotown	Vermont	506
1870	Konopelski Skyway	299	Leannside	Missouri	295
1871	Macejkovic Plains	857	Reinholdchester	Kansas	676
1872	Anika Harbor	052	Johnstonton	West Virginia	352
1873	Hoppe Mountain	405	Katrinashire	Louisiana	382
1874	Schimmel Views	823	South Derrick	Colorado	090
1875	Elta Street	595	South Nicolette	Kansas	541
1876	Rohan Junction	521	Lake Natalia	Delaware	549
1877	Stehr Expressway	807	Corwinborough	Washington	626
1878	Kunze Inlet	522	Shakirabury	Utah	668
1879	Leffler Road	767	Lonieland	Connecticut	298
1880	Turner Brook	603	New Billieborough	Oklahoma	880
1881	Jensen Run	297	North Uliseston	South Dakota	382
1882	Carolyne Terrace	070	North Alfred	Idaho	453
1883	Julia Knolls	353	Vaughnton	Hawaii	404
1884	Senger Ports	892	Enriqueland	Illinois	834
1885	Sanford Forest	402	Silasburgh	South Dakota	977
1886	Trace Locks	814	Wilbertburgh	Wyoming	415
1887	Carroll Mountain	821	Samarashire	Georgia	026
1888	Reinger Springs	437	Port Eldonville	Arkansas	748
1889	Blick Motorway	939	New Lydaland	Hawaii	952
1890	Feil Tunnel	992	Labadiehaven	Vermont	583
1891	Ebert Common	396	South Garth	Pennsylvania	226
1892	Effertz Manor	903	Ortizville	Indiana	036
1893	Gislason Grove	707	Palmamouth	Delaware	349
1894	Tracy Gateway	705	Armstrongside	South Dakota	859
1895	Batz Drives	406	South Norbertomouth	Mississippi	967
1896	Conroy Spurs	387	Walshmouth	Michigan	631
1897	Keven Shoal	699	Port Sydneeton	Iowa	400
1898	Wyman Glen	414	New Stacyberg	Ohio	689
1899	Lebsack Green	350	Kodymouth	Wisconsin	948
1900	Dalton Station	485	Elfriedaberg	Nebraska	668
1901	Avery Prairie	995	Okunevaton	Georgia	812
1902	Frankie Plaza	316	Hayesview	Tennessee	192
1903	Harmon Ridges	471	Howellside	Kentucky	103
1904	Pinkie Glens	947	New Rettaberg	Nebraska	800
1905	Zemlak Plains	570	Lake Judy	New York	876
1906	Madison River	494	Schusterport	Florida	692
1907	Nicolette Roads	883	Jaydenview	Virginia	468
1908	Hirthe Crossroad	022	West Cleorashire	Vermont	327
1909	Dare Passage	616	Port Mateoberg	Illinois	645
1910	Nathan Highway	577	West Leonbury	South Dakota	908
1911	Willms Street	257	Powlowskiville	Rhode Island	837
1912	Raven Port	346	Bergestad	Kentucky	839
1913	Ken Isle	804	Port Katherynside	Hawaii	070
1914	Morton Ville	499	Lake Marcelside	Iowa	405
1915	Jarrell Greens	501	Erdmanhaven	Pennsylvania	449
1916	Annetta Rapids	258	Torpmouth	Arizona	031
1917	Emelie Island	438	East Ara	Iowa	114
1918	Damion Haven	588	East Raehaven	Michigan	024
1919	Justyn Groves	018	North Londonfort	Montana	655
1920	Mazie Via	619	South Hiramborough	Georgia	322
1921	Wiley Lake	691	South Noelia	Washington	175
1922	Upton Forest	730	Jeramiemouth	Florida	992
1923	Zaria Vista	321	Mikelburgh	Tennessee	635
1924	McKenzie Throughway	549	New Eusebio	Louisiana	375
1925	Kilback Rue	666	Port Darrick	Mississippi	770
1926	Tianna Points	544	Dejashire	Colorado	442
1927	Asa Loaf	012	Kacieshire	Missouri	363
1928	Kessler Walks	811	Khalidmouth	South Dakota	494
1929	Dibbert Stravenue	684	East Shawn	Colorado	518
1930	Jayce Corner	053	West Shanny	Florida	180
1931	Turcotte Mountain	447	Cummeratahaven	Rhode Island	602
1932	Price Fort	865	Koelpintown	Illinois	671
1933	Veum Pass	181	Leonoraberg	Alaska	109
1934	Gloria Roads	962	Sigmundbury	New Hampshire	177
1935	Claudie Mountains	025	New Jennings	Nebraska	739
1936	Eliseo Garden	409	Port Marques	Idaho	762
1937	Anastasia Trace	289	Lake Olen	Utah	425
1938	Nettie Drives	359	Lake Jada	Texas	867
1939	Lisandro Estates	218	Lake Sonny	Louisiana	441
1940	Waelchi Drive	602	Port Jack	South Dakota	124
1941	Schiller Club	681	Jeffryborough	Nebraska	157
1942	Horace Green	059	New Andrew	Oklahoma	205
1943	Deondre Road	855	New Harrisonmouth	South Carolina	185
1944	Franecki Passage	336	Hilllville	Hawaii	444
1945	Cassidy Shoals	118	Greenholtton	Mississippi	257
1946	Nicole Road	152	West Oramouth	Arizona	578
1947	Logan Track	675	West Christyview	Hawaii	474
1948	Cullen Dam	719	Califort	Michigan	033
1949	Seth Square	494	Lindgrenview	Colorado	805
1950	Lenny Dale	437	Durganside	Vermont	295
1951	Paucek Roads	330	West Jeanton	South Dakota	102
1952	Nicola Highway	586	West Modesto	Rhode Island	223
1953	Lawson Orchard	038	New Leliabury	New York	056
1954	Strosin Street	213	Mayrastad	Vermont	577
1955	Botsford Estates	156	Stokesstad	Vermont	410
1956	Trevor Road	530	Ninamouth	Michigan	708
1957	Gleichner Parkway	586	East Kamrenborough	North Carolina	290
1958	Wolf Ferry	580	South Addisonfurt	Kentucky	363
1959	Lacey Street	593	Casperchester	Massachusetts	037
1960	Hilbert Point	792	Johnsside	Missouri	222
1961	Elna Harbors	702	South Jaimehaven	Michigan	875
1962	Mills Wells	036	West Velda	Oregon	530
1963	Bednar Pines	429	Marcusmouth	Mississippi	419
1964	Greg Vista	199	Schulistberg	Illinois	598
1965	Sheila Radial	911	Emelyside	Wisconsin	933
1966	Cummings Ridges	426	Jakubowskifurt	Oregon	574
1967	Fiona Springs	325	East Carleeburgh	Maine	435
1968	McKenzie Fall	587	New Ozellahaven	Montana	388
1969	Green Motorway	532	Lavernechester	Pennsylvania	123
1970	Williamson Locks	395	North Lynn	Florida	514
1971	Stephon Falls	689	Willmsberg	Wisconsin	001
1972	Kerluke Underpass	930	North Cierra	Ohio	367
1973	Schneider Tunnel	977	Smithamchester	Ohio	011
1974	Jayden Union	561	Port Kelsie	Mississippi	496
1975	Waters Summit	927	East Zena	South Dakota	886
1976	Leannon Path	256	Champlinburgh	Hawaii	405
1977	Weber Summit	411	Nolantown	Rhode Island	959
1978	Lilian Mission	650	Johannaborough	Michigan	414
1979	Stoltenberg Place	797	New Turner	Arkansas	985
1980	Fadel Land	244	Gayside	Indiana	188
1981	DuBuque Cove	425	New Zanestad	Oregon	244
1982	Queenie Expressway	008	New Zacheryborough	Oregon	666
1983	Cassin Ridges	442	East Teresatown	Nebraska	658
1984	Brennan Corners	504	Zarialand	California	489
1985	Wuckert Drive	885	Kuvalisbury	Oklahoma	667
1986	Elmo Pike	046	Kirlinburgh	Texas	214
1987	Jerrod Roads	099	Greenshire	Missouri	093
1988	Beatty Mall	216	West Vilma	Arizona	332
1989	Torphy Key	386	West Merrittfort	Oklahoma	515
1990	Johns Spurs	113	North Kaitlinton	Oklahoma	135
1991	Krista Row	826	Port Delia	Pennsylvania	511
1992	Lowe Forest	988	South Hans	Kansas	160
1993	Clark Trail	185	West Kenyattaborough	Rhode Island	672
1994	Nola Forge	544	Murazikview	North Dakota	085
1995	Lemke Mountains	204	Wileyview	Pennsylvania	607
1996	Altenwerth Ramp	176	Lake Gilberto	Kentucky	537
1997	Ruby Course	745	East Dillonside	Wisconsin	475
1998	Margie Orchard	511	Kuhlmantown	Utah	480
1999	Frami Common	555	Danielborough	Hawaii	790
2000	Grayce Village	648	North Brownstad	Massachusetts	781
2001	Hahn Bridge	167	Carabury	Wyoming	904
\.


--
-- TOC entry 4945 (class 0 OID 16522)
-- Dependencies: 220
-- Data for Name: storage_keeper; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.storage_keeper (phone_number, storage_id, first_name, last_name, email) FROM stdin;
+380001583480	1717	Lexi	Kihn	Marian_Murazik71@hotmail.com
+380002480772	1610	Jazmin	Bauch	Marion99@yahoo.com
+380002510340	1914	Emerson	Lemke	Freeman_Willms38@gmail.com
+380004157094	1583	Annabel	Sawayn	Nash_Conroy76@hotmail.com
+380006029567	1598	Neva	Hettinger	Adam.Brakus@hotmail.com
+380006100448	1517	Colt	Weber	Earl_Kohler@yahoo.com
+380006863900	1807	Llewellyn	Feil	Harvey.Sanford@yahoo.com
+380007981057	1744	Marion	Spinka	Sheldon79@hotmail.com
+380008026260	1584	Reynold	Stoltenberg	Clemens54@yahoo.com
+380009078569	1709	Amelie	Lesch	Sophia60@yahoo.com
+380009092468	1667	Scottie	Gutkowski	Consuelo_Leuschke9@hotmail.com
+380009140747	1650	Chance	Stark	Lavonne_Bartell@gmail.com
+380009807589	1986	Jerald	Pagac	Viola6@yahoo.com
+380010240753	1660	Damien	Herzog	Edmond.Vandervort9@yahoo.com
+380010483815	1786	Cydney	Little	Estevan_Mayert88@yahoo.com
+380011678131	1902	Brayan	Walsh	Laura.Kirlin85@gmail.com
+380011954439	1722	Brendan	Oberbrunner	Tianna.OReilly@gmail.com
+380013002392	1678	Vernice	Jones	Brennan.Powlowski34@hotmail.com
+380014162731	1835	Werner	Stehr	Bethany28@yahoo.com
+380014317026	1993	Isadore	Prohaska	Emile57@yahoo.com
+380014554292	1608	Chadrick	Franecki	Rickey49@hotmail.com
+380014685927	1595	Laverna	Daniel	Lawson_Jacobson@hotmail.com
+380014870641	1637	Graham	Block	Adrianna.Batz@gmail.com
+380015296285	1634	Trace	Reinger	Ettie66@yahoo.com
+380015355508	1987	Cristal	Pfeffer	Janiya.Cormier@gmail.com
+380017946521	1715	Samanta	Koss	Ernesto.Grant88@hotmail.com
+380019976245	1637	Leland	Halvorson	Alisha83@yahoo.com
+380020042600	1899	Manley	Kuhlman	Esmeralda12@yahoo.com
+380020084597	1889	Angelica	Kertzmann	Rowland.Purdy43@yahoo.com
+380020202713	1848	Vesta	Jacobs	Josephine4@yahoo.com
+380021210846	1894	Ed	Konopelski	Andy11@hotmail.com
+380021444842	1886	Dolores	Moore	Georgianna_Kunze7@yahoo.com
+380021996020	1611	Krystal	Kozey	Hipolito66@yahoo.com
+380023161150	1786	Rozella	Quitzon	Heloise.Hauck@gmail.com
+380023324280	1668	Hobart	Roberts	Javon.Jaskolski@gmail.com
+380023524502	1944	Dallas	Bergstrom	Lily40@gmail.com
+380023626087	1616	Judd	Boyer	Vicky79@hotmail.com
+380024028313	1865	Marlen	Frami	Gordon_Simonis46@gmail.com
+380024779827	1936	Ibrahim	Zemlak	Geovanny_Windler57@gmail.com
+380025428194	1625	Darrion	Turner	Ofelia_Lakin25@yahoo.com
+380025513905	1757	Sibyl	Lowe	Jeramy_Mosciski26@yahoo.com
+380025597203	1675	Estrella	Hoppe	Aylin13@gmail.com
+380025836839	1861	Martina	Medhurst	Antone_Jakubowski42@yahoo.com
+380026085092	1932	Zackery	D'Amore	Mylene7@yahoo.com
+380026603641	1773	Fae	White	Cortez_Von@gmail.com
+380026637234	1546	Maye	Block	Julian88@gmail.com
+380026831767	1985	Bailey	Braun	Rey_Sporer@gmail.com
+380028628281	1940	Itzel	Braun	Terrence.Jones@gmail.com
+380029654448	1614	Daron	Schoen	Nat.Gorczany@gmail.com
+380030833821	1612	Emma	Kovacek	Leland82@hotmail.com
+380032782299	1821	Evert	Pagac	Alec94@yahoo.com
+380032829692	1748	Thaddeus	Bosco	Annabelle17@yahoo.com
+380033942562	1641	Elwyn	Sipes	Curtis_Nienow@gmail.com
+380034071010	1683	Rey	Ferry	Golda76@gmail.com
+380034312231	1944	Lafayette	Walker	Zola.Kunde41@yahoo.com
+380035232675	1530	Mabel	Breitenberg	Bernadine_Heathcote51@yahoo.com
+380035857550	1889	Jovan	Sawayn	Ottilie68@hotmail.com
+380036304325	1561	Geraldine	Romaguera	Eddie24@gmail.com
+380037198571	1825	Erin	Paucek	George_DAmore@gmail.com
+380037669468	1800	Kacey	O'Hara	Dakota_Abbott@gmail.com
+380038292977	1638	April	Hirthe	Isaias_Crist@hotmail.com
+380038657147	1730	Eldon	Rowe	Eliseo29@hotmail.com
+380038853718	1628	Caesar	Wuckert	Dorthy.Koelpin16@yahoo.com
+380039420486	1628	Demario	Muller	Anastasia37@yahoo.com
+380039506099	1726	Minerva	Gottlieb	Gay_Goyette@hotmail.com
+380039908824	1521	Herminio	Langworth	Chet58@yahoo.com
+380040420823	1876	Marques	Hane	Jarod78@hotmail.com
+380042150718	1635	Maya	Ferry	Dashawn28@gmail.com
+380043750390	1993	Pasquale	Powlowski	Hosea_Ankunding@hotmail.com
+380043907096	1514	Annette	Altenwerth	Darien8@yahoo.com
+380044831320	1833	Ismael	O'Connell	Leanne_Dickens24@hotmail.com
+380045797287	2001	Grayson	Wiegand	Monte.Goldner@hotmail.com
+380046052408	1652	Edgardo	Labadie	Herman97@yahoo.com
+380046116607	1684	Sarah	Cronin	Brandyn.Bartoletti38@yahoo.com
+380046585015	1990	Danielle	Schumm	Genoveva.Armstrong36@hotmail.com
+380047174009	1910	Letitia	Spencer	Cayla94@gmail.com
+380047583347	1692	Joelle	Adams	Lacey30@yahoo.com
+380048150027	1962	Deron	Reichel	Sadye64@yahoo.com
+380050043172	1613	Boyd	Breitenberg	Haven10@gmail.com
+380050238302	1976	Darian	King	Jarred58@yahoo.com
+380050335844	1669	America	Fadel	Geovanny.Johnston@hotmail.com
+380050706680	1698	Rahul	Kling	Marcelo_Heller@hotmail.com
+380050934663	1601	Graham	Hamill	Mariano.Yost@hotmail.com
+380051465465	1602	Briana	Borer	Felicia22@yahoo.com
+380052243434	1539	Adella	Ferry	Claudia_Schamberger21@yahoo.com
+380053336752	1720	Kaia	Purdy	Rollin_Connelly@yahoo.com
+380007915733	1835	Adell	Murazik	Erna.Olson@yahoo.com
+380054281134	1661	Kirk	O'Keefe	Ashly42@gmail.com
+380055407484	1861	Gerald	Towne	Myriam.Torphy94@gmail.com
+380055746349	1598	Allan	Carroll	Kaleb61@gmail.com
+380056136406	1697	Burdette	Langosh	Jasen55@hotmail.com
+380057914220	1699	Audie	Koss	Joshuah_Purdy@yahoo.com
+380059319721	1948	Robin	Hills	Ida51@gmail.com
+380059474036	1941	Robyn	Schultz	Mariela98@hotmail.com
+380060021141	1833	Leanna	Schuster	Anibal_Mitchell23@gmail.com
+380060441621	1927	Colleen	Kuphal	Enoch84@hotmail.com
+380060676980	1552	Serena	Legros	Rusty25@hotmail.com
+380061908449	1935	Gerson	Osinski	Gabriel_Nolan@gmail.com
+380062265576	1828	Delta	Kirlin	Greta.Casper@yahoo.com
+380063091956	1985	Kayleigh	Schimmel	Jocelyn.Pagac@hotmail.com
+380064008876	1541	Leonora	Murphy	Chadrick_Vandervort9@hotmail.com
+380064104924	1606	Rogelio	Monahan	Santa.Swaniawski@gmail.com
+380064345700	1874	Pinkie	Satterfield	Amalia_Luettgen@yahoo.com
+380064391229	1618	Joshuah	Powlowski	Irma.OConnell@hotmail.com
+380065243660	1942	Breana	Beer	Brice17@yahoo.com
+380067162067	1920	Sylvester	Hackett	Amara_Gutmann@gmail.com
+380068897194	1859	Cortney	Murphy	Henri93@hotmail.com
+380069712530	1998	Josiane	Kreiger	Destiny_Little@yahoo.com
+380069791795	1964	Aiyana	Abernathy	Jo.Schiller97@hotmail.com
+380069974051	1998	Norberto	Schmeler	Charlie.Labadie@hotmail.com
+380070491277	1671	Jalyn	Doyle	Cydney27@hotmail.com
+380071382109	1728	Oren	Bins	Janae.Romaguera33@yahoo.com
+380071582795	1752	Kamryn	Rath	Kelvin86@hotmail.com
+380071680320	1677	Donna	Boehm	Heaven_Auer37@gmail.com
+380072203135	1883	Marisa	Hammes	Waldo68@hotmail.com
+380072970355	1772	Lenore	Osinski	Darion_Renner@gmail.com
+380073749770	1588	Marcellus	Veum	Kaylah21@hotmail.com
+380074231170	1849	Rosalind	Ruecker	Misael_Mayert@yahoo.com
+380074829933	1786	Billy	Medhurst	Carlotta48@hotmail.com
+380077712055	1859	Miguel	Terry	Destiny15@hotmail.com
+380077849983	1640	Maximo	Hartmann	Jess.Schaden@gmail.com
+380078666689	1611	Keagan	Lockman	Ernesto_Grimes@gmail.com
+380079446974	1639	Richie	Herzog	Monte75@hotmail.com
+380080263098	1565	Aaliyah	Walker	Johann65@gmail.com
+380080388574	1539	Christopher	Kihn	Lillian_Rath@hotmail.com
+380082349636	1924	Royce	Block	Keith70@hotmail.com
+380082738354	1836	Alexane	Labadie	Helmer7@yahoo.com
+380082845085	1702	Tommie	Sanford	Wilson_Langosh40@gmail.com
+380083538091	1508	Everette	Mante	Verner.Langosh@hotmail.com
+380083787790	1579	Manuela	Lehner	Stephan57@yahoo.com
+380086498598	1831	Heaven	Daniel	Heber33@gmail.com
+380087805165	1529	Michele	Rohan	Mattie_Abbott@hotmail.com
+380088767117	1674	Margarette	Rutherford	Glennie_Feest@yahoo.com
+380088927351	1823	Alanis	Fritsch	Cindy.Smith@hotmail.com
+380089645156	1981	Jude	Weimann	Cielo11@yahoo.com
+380090191140	1721	Derek	Nicolas	Juliet11@yahoo.com
+380090793609	1987	Brielle	Nader	Yesenia69@hotmail.com
+380090803939	1658	Estefania	Beier	Raina1@yahoo.com
+380091611683	1883	Maudie	Larson	Anna.Fay@hotmail.com
+380092039838	1573	Eusebio	Bernier	Doyle_Jacobson58@gmail.com
+380092805910	1947	Gretchen	Jakubowski	Damaris.Beatty62@yahoo.com
+380092917003	1610	Bennie	Beer	Rickey.Collier@yahoo.com
+380094018957	1858	Paolo	Runolfsdottir	Estel.Kerluke@hotmail.com
+380094472721	1585	Anjali	Rowe	Jaclyn_Schumm47@gmail.com
+380094486576	1960	Lester	Braun	Ara55@yahoo.com
+380094573945	1659	Tracy	Wolff	Alexandre34@yahoo.com
+380095105221	1706	Vanessa	Ortiz	Ruben81@gmail.com
+380095157276	1846	Stephania	Runte	Elton_Schamberger@hotmail.com
+380095332466	1691	Erwin	Kuphal	Alison_Kreiger72@hotmail.com
+380096203340	1976	Madonna	Wilkinson	Rusty.Reinger76@yahoo.com
+380096360126	1761	Desiree	Senger	Jaqueline_Kassulke0@hotmail.com
+380096775866	1748	Bethel	Wolff	Georgette.Turner@yahoo.com
+380098041414	1828	Dejuan	Schmeler	Marilie91@hotmail.com
+380098547994	1769	Oma	Beier	Marguerite.Kassulke59@hotmail.com
+380100414351	1557	Geo	McKenzie	Imani_Satterfield@hotmail.com
+380101514204	1515	Karine	Ferry	Connor_Mosciski@gmail.com
+380103176033	1545	Caesar	Mosciski	Rosalinda38@gmail.com
+380103180146	1531	Adella	Muller	German.Ondricka17@gmail.com
+380103595896	1946	Dan	Wunsch	Berta.Stiedemann49@gmail.com
+380103980442	1571	Karen	Beatty	Bridgette_Cartwright@gmail.com
+380103983237	1624	Emil	Koelpin	Shyann_Lowe56@hotmail.com
+380104356050	1934	Joanne	Lang	Gabe66@gmail.com
+380104692559	1573	Katelin	Schoen	Seth_Gislason@gmail.com
+380104945288	1532	Stuart	Gusikowski	Maria52@gmail.com
+380104968536	1684	Caleb	Beatty	Jasen_Bailey@hotmail.com
+380106087463	1701	Martin	Walsh	Elenora_Ward@yahoo.com
+380106418887	1582	Carli	Koch	Bert.Bode@yahoo.com
+380106541515	1759	Jeramy	Rath	Rico39@yahoo.com
+380107233696	1768	Lou	Littel	Colby_Kling99@hotmail.com
+380107933082	1687	Justine	Stamm	Kaley.Hayes@yahoo.com
+380108113356	1696	Joe	Schuster	Thomas37@yahoo.com
+380108324450	1520	Francis	Breitenberg	Bradley.Mann53@hotmail.com
+380108384145	1748	Verlie	Dooley	Flossie_Ortiz@hotmail.com
+380108797551	1967	Teresa	Mayer	Jimmy.Hodkiewicz@hotmail.com
+380109893740	1760	Mozelle	Hammes	Aric_Schimmel@yahoo.com
+380110817184	1528	Mitchell	Bashirian	Astrid_Roob@gmail.com
+380112024854	1692	Carmella	O'Connell	Cassandre_Hackett@yahoo.com
+380112185263	1930	Rickey	Kautzer	Chanelle.Upton@hotmail.com
+380112370354	1937	Everett	Veum	Conner.Beahan@hotmail.com
+380113506397	1559	Vilma	Rau	Rosie.Kuhlman@yahoo.com
+380114889375	1522	Nat	Murphy	Haven.Swift@yahoo.com
+380115423095	1966	Collin	Kshlerin	Kiera.Littel@hotmail.com
+380115935999	1996	Macey	Grady	Anastacio.Jones@gmail.com
+380116085824	1790	Jakob	Funk	Hazel96@gmail.com
+380116726640	1831	Thelma	Stanton	Newell_Shields71@gmail.com
+380116931364	1795	Braxton	Davis	Corine_Langworth@hotmail.com
+380116961675	1855	Cortez	Schneider	Sonia93@hotmail.com
+380117231498	1728	Cleta	Labadie	Jewel.Lowe45@gmail.com
+380118355652	1955	Shawn	Bauch	Lauryn.Kassulke89@yahoo.com
+380118536165	1673	Xzavier	Macejkovic	Oscar_Heaney@yahoo.com
+380119377884	1691	Kiarra	Muller	Emelia_Witting@hotmail.com
+380119468346	1782	Helena	Boehm	Violet_Pfannerstill@gmail.com
+380121424828	1940	Rosamond	Beer	Americo_Turner@yahoo.com
+380122857311	1921	Delpha	Bahringer	Keon_Tromp8@yahoo.com
+380123024644	1907	Summer	Abernathy	Lisandro44@gmail.com
+380123245091	1705	Margot	Upton	Hattie.Fritsch@gmail.com
+380124777769	1964	Jody	Metz	Cassie_Monahan85@yahoo.com
+380125133113	1982	Lorna	Prohaska	Jerel.Brakus91@gmail.com
+380125843677	1598	Penelope	Gottlieb	Onie.Blick64@yahoo.com
+380125991574	1531	Audie	Kunde	Claudine.Auer10@yahoo.com
+380125997470	1837	Cale	Fahey	Alford.Keebler@hotmail.com
+380127463810	1966	Sabina	Shanahan	Scottie11@yahoo.com
+380127485742	1820	Austin	Schmitt	Marlin_Pfeffer@gmail.com
+380127660790	1794	Kristin	Howell	Schuyler_Schimmel80@gmail.com
+380127811113	1535	Veda	Heaney	Fabiola.Tremblay6@yahoo.com
+380129498125	1937	John	Dooley	Gilberto.Witting@yahoo.com
+380129617275	1799	Helen	Herzog	Marianna.Bins20@yahoo.com
+380129857179	1699	Aric	Bernier	Verdie.Gottlieb80@hotmail.com
+380130039985	1730	Cathrine	Langworth	Reese69@hotmail.com
+380130340904	1955	Georgianna	Halvorson	Madaline_Waters@hotmail.com
+380130814994	1780	Willis	Auer	Carley.Hudson8@yahoo.com
+380131351755	1796	Mona	Spinka	Orpha_Greenholt9@yahoo.com
+380131475609	1623	Corene	McKenzie	Alan_Emmerich87@hotmail.com
+380131503307	1679	Reyna	Jacobson	Devyn_Smith56@hotmail.com
+380131741540	1680	Christop	Shields	Darryl37@hotmail.com
+380131834082	1971	Jarrett	Cassin	Cathrine_Klocko@gmail.com
+380131918414	1585	Keaton	Fritsch	Noelia_DuBuque@yahoo.com
+380131925978	1707	River	Moore	Bruce29@gmail.com
+380132833837	1607	Monroe	O'Hara	Adell_Schulist93@gmail.com
+380133840870	1658	Loraine	Bernhard	Rhiannon.Armstrong@hotmail.com
+380134368134	1762	Maxie	Maggio	Thelma43@hotmail.com
+380134815529	1567	Larissa	Stamm	Lonny_Schinner82@yahoo.com
+380136900059	1505	Gabrielle	Haley	Earlene_Kohler@gmail.com
+380139535921	1650	Kristofer	Leuschke	Elliot92@hotmail.com
+380139738246	1661	Albina	Baumbach	Brock_Mraz@hotmail.com
+380142319053	1954	Magnus	Kshlerin	Otto2@hotmail.com
+380143081193	1643	David	Gerhold	Jonathon73@gmail.com
+380145474456	1903	Dulce	Bergnaum	Dianna_Glover@gmail.com
+380146211060	1529	Elwin	O'Connell	Dexter43@gmail.com
+380146781743	1776	Ava	Runte	Maximillian_Boyle@hotmail.com
+380147574296	1616	Cindy	Jerde	Ethel_Kling31@gmail.com
+380147958424	1504	Marcelo	Rippin	Krystal93@yahoo.com
+380148180832	1776	Arlie	Blick	Greyson_Medhurst@hotmail.com
+380148731293	1628	Bettie	Mayert	Carolina47@gmail.com
+380149275386	1660	Randal	Conroy	Crystel9@hotmail.com
+380150450704	1658	Trent	Kuvalis	Miller.Nitzsche33@yahoo.com
+380151211879	1961	Freddy	Baumbach	Gerardo52@yahoo.com
+380151277750	1584	Ezekiel	McCullough	Luciano_Kuhic@yahoo.com
+380151994437	1567	Austyn	Baumbach	Alaina.Kiehn@hotmail.com
+380152280627	1648	Kellie	Emmerich	Ernestine.Windler@hotmail.com
+380152696302	1775	Einar	Zboncak	Deondre41@hotmail.com
+380152855366	1969	Schuyler	Leannon	Marlen98@gmail.com
+380153311134	1557	Xander	Grady	Jonathon.Hermann@gmail.com
+380153601561	1773	Philip	Daniel	Hosea_Davis@gmail.com
+380154940713	1987	Thelma	Rempel	Tod38@gmail.com
+380156066512	1512	Cordell	Windler	Gilbert87@gmail.com
+380157457650	1608	Elda	Langworth	Ayden83@yahoo.com
+380158002644	1880	Madge	Predovic	Lucius.Pouros43@yahoo.com
+380159553650	1890	Kitty	Sawayn	Flo.Witting@gmail.com
+380160399603	1998	Garland	Bernier	Selena.Bayer@yahoo.com
+380160703104	1654	Fatima	Shields	Megane21@gmail.com
+380162253458	1583	Buford	Emmerich	Willard56@hotmail.com
+380162324345	1538	Immanuel	Bergstrom	Amos.Jones@gmail.com
+380162588026	1739	Charlene	Douglas	Leif45@hotmail.com
+380164024188	1686	Katharina	Johnston	Jessie93@hotmail.com
+380165106695	1867	Valentine	Weimann	Kennedy.Baumbach44@gmail.com
+380165525642	1848	Noemie	Effertz	Noemi_Koepp68@yahoo.com
+380165628327	1895	Felicita	Buckridge	Kaleb.Boehm@hotmail.com
+380165729316	1797	Marta	Kuvalis	Adrienne_Wiza@hotmail.com
+380166864572	1866	Alvis	Morar	Veronica.Altenwerth93@gmail.com
+380167747681	1704	Zack	Reynolds	Sharon86@hotmail.com
+380168039192	1857	Morris	Hills	Orland.Kihn@gmail.com
+380168225767	1625	Chad	Frami	Manuel.Powlowski@hotmail.com
+380169354685	1667	Kristian	Funk	Dale_Marvin70@yahoo.com
+380169378642	1683	Josiah	Murphy	Ivory73@hotmail.com
+380170031782	1555	Ari	Emmerich	Stevie_Stark@gmail.com
+380170116408	1720	Clovis	D'Amore	Cletus9@hotmail.com
+380170325772	1629	Brandy	Strosin	Joey.Lynch@yahoo.com
+380001409943	1834	Gus	Steuber	\N
+380170962201	1529	Norene	Hermann	Justice99@gmail.com
+380171226685	1644	Linnea	Reichel	Herman64@yahoo.com
+380173146951	1932	Jett	Dare	Audie_Wolf@yahoo.com
+380173296624	1729	Stuart	Herman	Jeremy_Emmerich@hotmail.com
+380173898866	1717	Keeley	Huels	Marquis.Stiedemann54@gmail.com
+380174514899	1843	Carley	Hamill	Litzy67@yahoo.com
+380179871999	1802	Francisco	Bergnaum	Alvah.Zulauf26@hotmail.com
+380182035791	1505	Delia	Klocko	Aurelie70@hotmail.com
+380185906287	1883	Alan	Schaden	Finn94@hotmail.com
+380186702564	1841	Carlee	Breitenberg	Carson.Botsford@yahoo.com
+380187999726	1529	Andres	Casper	Kennith_Daugherty99@yahoo.com
+380189093257	1985	Gus	Corwin	Oma.Satterfield82@hotmail.com
+380189381246	1922	Adolfo	Bernier	Will.Harvey39@yahoo.com
+380189795342	1735	Lupe	Spinka	Kendra11@gmail.com
+380190073394	1541	Marley	Gulgowski	Evert.Langworth41@hotmail.com
+380190608287	1952	Nathanial	Botsford	Retha68@yahoo.com
+380191663620	1713	Vernie	Hintz	Shane_Runte@hotmail.com
+380191973338	1530	Ethel	Streich	Adelbert51@gmail.com
+380193122997	1993	Hassie	West	Ruby19@hotmail.com
+380193313588	1840	Dannie	Abshire	Reanna47@yahoo.com
+380194193465	1923	Brenna	Lehner	Lew4@yahoo.com
+380194478208	1860	Mose	Smitham	Angelita81@yahoo.com
+380195519123	1786	Otis	Upton	Dortha31@yahoo.com
+380195633816	1633	Kamille	Hirthe	Kathlyn_Gislason@gmail.com
+380195862297	1743	Michaela	Yost	Augustine_Bruen@yahoo.com
+380196510121	1692	Eula	Hane	Jonatan.Schultz@hotmail.com
+380197638120	1663	Norval	Rolfson	Mireille.Hessel@gmail.com
+380198099497	1718	Kevon	Marvin	Twila.Dietrich@gmail.com
+380199927270	1650	General	Labadie	Claudie30@gmail.com
+380199996231	1508	Tobin	Cummerata	Alene_Gleichner28@yahoo.com
+380200067433	1593	Darron	Collier	Elnora.Bartell@gmail.com
+380200078979	1975	Helena	Willms	Virgil.Mraz@gmail.com
+380200997400	1594	Adella	Rau	Christina33@yahoo.com
+380201509906	1503	Kristopher	Lockman	Monte.Greenholt24@yahoo.com
+380202103013	1869	Devonte	Marks	Webster_Padberg@gmail.com
+380202627247	1995	Ivy	Zulauf	Davon_Pouros47@yahoo.com
+380202682164	1920	Roselyn	Funk	Shany44@yahoo.com
+380204102107	1868	Rosendo	Jacobi	Gladyce_Powlowski@yahoo.com
+380205407584	1928	Willis	Feeney	Maryse76@yahoo.com
+380209429553	1812	Carmen	Mosciski	Doyle82@hotmail.com
+380209896604	1877	Victoria	Aufderhar	Carey_Kihn13@hotmail.com
+380210849018	1531	Natasha	Hills	Alisha_Thiel@hotmail.com
+380211155818	1616	Alfreda	Hayes	Jamey.Lakin@yahoo.com
+380213236678	1849	Brannon	Murray	Carlos_Wintheiser@yahoo.com
+380213959370	1669	Jerome	Wyman	Jeanie.Thompson52@gmail.com
+380216283705	1624	Wilber	Cole	Roman.Smith52@yahoo.com
+380216388882	1613	Alden	Schmidt	Kale88@yahoo.com
+380216405362	1970	Jailyn	Cummerata	Dortha_Mann@yahoo.com
+380217325153	1894	Hillary	Wilkinson	Cloyd.Robel91@hotmail.com
+380217607492	1892	Reid	Bode	Aliyah50@gmail.com
+380218641812	1849	Harold	Senger	Elijah_Roob28@hotmail.com
+380218749333	1769	Okey	Schroeder	Candace.Kreiger@yahoo.com
+380219328642	1596	Dario	Littel	Garland.Goodwin@gmail.com
+380219871288	1685	Frank	Welch	Jude78@hotmail.com
+380220272315	1968	Turner	Koch	Nicola31@gmail.com
+380220507996	1535	Kayli	Miller	Carlee31@hotmail.com
+380220613028	1556	Alyce	Schultz	Vada_Kulas44@hotmail.com
+380220634342	1803	Celestino	Goodwin	Brooks_Legros@hotmail.com
+380221266483	1632	Lela	Swaniawski	Lewis85@yahoo.com
+380222032641	1514	Kelvin	Franecki	Magdalen_Gleason@hotmail.com
+380222324988	1696	Rosamond	Baumbach	Justen.Hand10@yahoo.com
+380222465773	1861	Daphnee	Gutkowski	Kenna_Bashirian67@yahoo.com
+380223212269	1664	Aiden	Jaskolski	Isai_Collins28@gmail.com
+380223452335	1662	Myrtice	Brakus	Marlee_Frami@yahoo.com
+380223567843	1659	Nolan	Simonis	Barney7@hotmail.com
+380223925096	1810	Green	Jones	Kane98@hotmail.com
+380224174601	1504	Juanita	Prohaska	Rubie_Moen@yahoo.com
+380224432039	1999	Marjory	Howe	Norris89@hotmail.com
+380225442864	1830	Margarete	Balistreri	Kellen_Weber13@hotmail.com
+380226272158	1523	Dawson	Kuhlman	Rowena41@gmail.com
+380227363115	1673	Polly	Wiza	Braden.Simonis97@hotmail.com
+380228220559	1925	Matilde	Shanahan	Coby.Huel@yahoo.com
+380228277422	1505	Jackie	Hudson	Melisa_Barrows@yahoo.com
+380228390515	1616	Erik	Sawayn	Myrl_Bailey81@gmail.com
+380230249090	1711	Louisa	Bosco	Bud_Kohler@gmail.com
+380230624613	1903	Hudson	Kihn	Earline12@hotmail.com
+380231111433	1508	Alexis	Bayer	Monserrate84@gmail.com
+380231655993	1914	Elfrieda	Langworth	Della_Koepp79@hotmail.com
+380232027681	1722	Hal	Ziemann	Max_Beahan89@gmail.com
+380232263853	1899	Aliyah	Osinski	Bernhard_Langosh@yahoo.com
+380232633929	1859	Lavonne	Schiller	Herminio.Veum6@gmail.com
+380232897722	1690	Cordelia	Parker	Sabrina.Altenwerth94@yahoo.com
+380233524461	1755	Gardner	Schoen	Afton13@gmail.com
+380233538397	1947	Evelyn	Langosh	Fredrick42@yahoo.com
+380233557626	1699	Woodrow	Hammes	Annamae63@hotmail.com
+380234033341	1687	Tyra	Bednar	Julie_Ward@yahoo.com
+380234146963	1819	Jacey	Little	Maggie.Johnson40@yahoo.com
+380235884705	1974	Vernon	Dooley	Kiana.Wisoky4@gmail.com
+380236700109	1675	Delpha	Abbott	Serenity.Cruickshank@yahoo.com
+380237366998	1652	Jammie	Schimmel	Antonetta_Turcotte86@hotmail.com
+380237994594	1640	Regan	Carter	Adeline.Wehner1@gmail.com
+380238442027	1826	Rowena	Collins	Jacques.Runte24@hotmail.com
+380239253431	1802	Trevion	Jenkins	Lucy_Waters@yahoo.com
+380239477859	1843	Karlee	Bins	Torrey_Powlowski@yahoo.com
+380240091301	1574	Callie	Auer	Hollie.Shields84@yahoo.com
+380240629200	1629	Wendy	Schowalter	Kamille_Mills@gmail.com
+380241127335	1556	Ansley	Zemlak	Augustine92@hotmail.com
+380241167411	1537	Elenor	Balistreri	Claudine11@gmail.com
+380241356328	1632	Jarrod	Kirlin	Dahlia.Schamberger86@hotmail.com
+380241365766	1637	Arnoldo	Kiehn	Rebeca.Rosenbaum51@yahoo.com
+380241659212	1746	Katarina	Flatley	Ivy.Aufderhar@hotmail.com
+380242440016	1681	Susie	Kilback	Sherman_Koepp81@yahoo.com
+380243969096	1585	Jensen	Douglas	Susana.Graham@gmail.com
+380244253050	1638	Rhett	Baumbach	Susanna56@hotmail.com
+380244405101	1830	Jimmie	Willms	Ansel.Medhurst45@yahoo.com
+380245125595	1595	Nasir	Hickle	Estella.OConner@hotmail.com
+380247337576	1761	Catharine	Huel	Yvonne10@hotmail.com
+380248284435	1892	Sabryna	Roberts	Betsy5@hotmail.com
+380249484300	2000	Rasheed	Collins	Curt5@gmail.com
+380249689055	1615	Luis	Ullrich	Alayna5@yahoo.com
+380249958301	1972	Madie	Ruecker	Robert.Jacobi16@gmail.com
+380252114698	1646	Sydnie	Hayes	Moses_Hayes45@hotmail.com
+380253707533	1783	Lonnie	Towne	Richard.Rosenbaum4@hotmail.com
+380254187094	1951	Elmer	Casper	Clementina98@gmail.com
+380254408360	1557	Savion	Hoppe	Anderson_Murray35@gmail.com
+380254961404	1888	Pietro	Kunde	Roy33@gmail.com
+380254974192	1646	Tyson	Witting	Victoria_Koelpin97@hotmail.com
+380255527693	1630	Janis	Gerlach	Jean_Jerde30@gmail.com
+380256391078	1915	Sallie	Robel	Dion54@yahoo.com
+380256861247	1614	Pierre	Boyer	Braden_Collier69@gmail.com
+380256897033	1973	Julianne	Herman	Douglas.Cronin18@gmail.com
+380258303711	1860	Cordelia	Wilkinson	Abel.Rowe16@yahoo.com
+380258457119	1973	Karolann	Jakubowski	Issac.Nitzsche14@hotmail.com
+380258524276	1568	Bella	Renner	Anita_Waters76@hotmail.com
+380258649996	1642	Otto	Torphy	Luisa_Lockman20@yahoo.com
+380258653327	1509	Stuart	Smitham	Elroy.Haag21@yahoo.com
+380259390193	1699	Kamryn	Block	Camylle.Heller64@yahoo.com
+380259863739	1963	Sigurd	Prosacco	Irving_Cole@gmail.com
+380263837665	1759	Ardella	Emmerich	Buford_Wisozk@yahoo.com
+380264480053	1629	Nicklaus	Brown	Whitney7@gmail.com
+380265290746	1833	Edd	Blanda	Althea.Jacobs@yahoo.com
+380265427308	1697	Modesto	Johnson	Kenyatta9@hotmail.com
+380265679989	1900	Maritza	Hoeger	Baron.Mante44@hotmail.com
+380267166805	1506	Scarlett	Ritchie	Guiseppe.Abernathy@hotmail.com
+380268387265	1946	Alize	Von	Kathryne_Aufderhar@hotmail.com
+380269379806	1704	Peggie	Conroy	Clinton_Koch55@gmail.com
+380270780830	1622	Sydney	Maggio	Rita.Hudson@hotmail.com
+380270982976	1768	Francisco	Raynor	Jamal_Waters@yahoo.com
+380271013167	1957	Dillan	Tromp	Marcia_Gulgowski58@yahoo.com
+380271388743	1578	Gabe	Wuckert	Cornelius20@yahoo.com
+380272197522	1614	Kayli	O'Keefe	Jevon.Waters@yahoo.com
+380273176119	1872	Adella	Mertz	Rachel12@gmail.com
+380273472436	1887	Aliza	Bogisich	Birdie10@hotmail.com
+380273476663	1731	Jaida	Sporer	Mozelle44@hotmail.com
+380274015906	1730	Roger	Orn	Nicklaus98@gmail.com
+380275291482	1848	Brady	Lockman	Vickie86@hotmail.com
+380277138684	1564	Abbey	Dach	Dewayne77@gmail.com
+380277691421	1690	Bernita	Conn	Enoch39@gmail.com
+380277778144	1619	Heather	Torphy	Leif.Bednar54@gmail.com
+380278068791	1905	Jose	Ward	Lorenza19@gmail.com
+380278374630	1708	Toney	McClure	Dena_Pouros8@yahoo.com
+380278478895	1733	Damon	Rogahn	Henderson26@yahoo.com
+380278738340	1801	Lamont	Kessler	Oliver.Russel@hotmail.com
+380278772992	1918	Juanita	Boehm	Leann.Kovacek7@hotmail.com
+380279265665	1978	Bridgette	Brown	Chester.Schimmel70@gmail.com
+380280448648	1562	Alanis	Olson	Pattie17@hotmail.com
+380281372183	1950	Jacey	Larson	Rickey87@gmail.com
+380282763142	1551	Vernice	Konopelski	Arianna_Bernhard56@gmail.com
+380283689322	1779	Dakota	Zemlak	Meta.Kihn60@hotmail.com
+380284267338	1504	Emmet	Collier	Ashlynn_Bergnaum@hotmail.com
+380284663850	1911	Timothy	Schumm	Ardella15@hotmail.com
+380286007249	1937	Russell	Rosenbaum	Vaughn.Kub38@yahoo.com
+380286533179	1621	Adaline	Williamson	Madalyn_Kris58@gmail.com
+380288413755	1514	Mossie	Thiel	Sophie.Quitzon@hotmail.com
+380288890856	1958	Gust	Armstrong	Aniyah_Yundt78@gmail.com
+380289152707	1982	Delmer	Heathcote	Barrett66@hotmail.com
+380289395569	1511	Rico	Grady	Bethany89@yahoo.com
+380289912583	1661	Casandra	Turner	Zackery43@gmail.com
+380291155779	1527	Hubert	Mosciski	Benton.Reinger19@hotmail.com
+380291245798	1706	Dana	Schuster	Naomi_Torp68@yahoo.com
+380291623540	1968	Angelica	Tromp	Scot69@hotmail.com
+380292008118	1838	Dan	Lakin	Cathrine.Harris35@hotmail.com
+380292042899	1641	Adonis	Ullrich	Lauren3@hotmail.com
+380295772098	1937	Rogelio	Steuber	Jonatan75@hotmail.com
+380296030006	1956	Rupert	Cassin	Dayana.Grady@gmail.com
+380296250976	1601	Isabel	Rohan	Leslie79@gmail.com
+380296462406	1914	Mariane	Harvey	Aidan.Nikolaus@gmail.com
+380297703655	1607	Jaylan	McLaughlin	Roma19@gmail.com
+380298370869	1681	Alvina	Mayert	Maxime.Macejkovic@hotmail.com
+380298402013	1683	Amari	Hyatt	Clyde.Gutmann@gmail.com
+380298545258	1729	Rogers	Kuvalis	Darrel_Jast4@hotmail.com
+380299042034	1928	Rosemarie	Feeney	Reymundo_Ondricka7@gmail.com
+380299541042	1515	Jarrell	Schamberger	Helene.Tillman53@gmail.com
+380300039028	1722	Verlie	Ondricka	Betsy.Crooks@hotmail.com
+380300871886	1917	Talon	Zboncak	Rebekah.Heidenreich36@yahoo.com
+380301148749	1584	Aubrey	O'Connell	Julianne.Bailey@gmail.com
+380301576340	1754	Nick	Schimmel	Lesly_Nikolaus@yahoo.com
+380302584813	1970	Madisen	Muller	Karson.Bradtke56@yahoo.com
+380303187581	1823	Arnulfo	McCullough	Emery.Schinner@yahoo.com
+380303593720	1716	Jose	Klein	Jayme.Larkin@hotmail.com
+380303640157	1732	Garry	Tremblay	Alexander.Conroy@hotmail.com
+380303980209	1949	Serena	Romaguera	Clotilde42@gmail.com
+380304132276	1915	Floyd	Wiza	Catherine.Will94@hotmail.com
+380304591408	1601	Dallin	Leuschke	Frederick_Zemlak82@yahoo.com
+380305253392	1987	Kristian	Walter	Jalyn.Murazik@hotmail.com
+380306670721	1730	Stephan	Schroeder	Marianna29@gmail.com
+380306763479	1604	Mauricio	Willms	Ashlee33@gmail.com
+380306818510	1629	Cooper	Fahey	Pearlie_Cummerata60@hotmail.com
+380307368527	1571	Christine	Daniel	Fritz.Kozey82@gmail.com
+380307787745	1685	Walker	Roob	Kaylin.Romaguera@gmail.com
+380308085875	1976	Annalise	Baumbach	Turner3@yahoo.com
+380308189710	1602	Wava	Raynor	Reese43@hotmail.com
+380308766884	1984	Ocie	Green	Jacinto_Smith17@gmail.com
+380309985534	1714	Edmund	Schumm	Marielle.Kutch68@hotmail.com
+380310015837	1906	Verlie	Rolfson	Breana69@gmail.com
+380310165196	1606	Libbie	Hintz	Cheyenne3@hotmail.com
+380311897200	1645	Dangelo	Jerde	Rodrigo_Smith35@hotmail.com
+380312672754	1509	Caleb	Abbott	Clare96@yahoo.com
+380312752631	1998	Audie	Koepp	Stewart_McKenzie46@gmail.com
+380313305331	1611	Blaze	Lueilwitz	Alva.Weissnat@gmail.com
+380314938945	1897	Nyasia	Wilderman	Malinda.Leffler@hotmail.com
+380316211976	1816	Howell	Kohler	Darrel84@gmail.com
+380317099925	1740	Mervin	Lueilwitz	Garrick_Greenholt93@hotmail.com
+380317407810	1770	Mercedes	Hirthe	Pasquale97@yahoo.com
+380317547492	1525	Boris	Lubowitz	Gwendolyn86@hotmail.com
+380317768885	1809	Demetrius	Stark	Cleveland1@yahoo.com
+380318632606	1813	Rhoda	Yost	Edyth3@gmail.com
+380319023074	1533	Angie	Shanahan	Katlyn_Hodkiewicz@yahoo.com
+380319110007	1696	Esteban	Russel	Destini52@hotmail.com
+380319413716	1915	Trystan	Grady	Annabell_Friesen@hotmail.com
+380321207184	1846	Donna	Walker	Kylee.Sawayn99@hotmail.com
+380322462521	1848	Cameron	Runolfsdottir	Lauretta_Johnston@gmail.com
+380323829577	1697	Larue	Barrows	Bailee.Block@yahoo.com
+380325870740	1735	Cordell	Harris	Hardy67@gmail.com
+380327675624	1554	Timmothy	Kuhn	Talia62@gmail.com
+380328023671	1962	Lawrence	Kulas	Cierra_White23@gmail.com
+380328886266	1563	Callie	Effertz	Lavonne_Hessel@gmail.com
+380331096045	1505	Cielo	Welch	Paula_Hayes@gmail.com
+380331860980	1827	Donald	Raynor	Heidi.OConnell@yahoo.com
+380331893323	1531	Ilene	Franecki	Giovani_Flatley@hotmail.com
+380332189778	1907	Obie	Beier	Rhiannon.OHara52@hotmail.com
+380332858863	1633	Freeman	Prosacco	Dino94@hotmail.com
+380334339338	1693	Afton	Frami	Mortimer.Maggio51@gmail.com
+380336355787	1664	Hector	Feeney	Fidel.Greenholt12@gmail.com
+380338814894	1682	Domenica	Flatley	Sydni_Vandervort@gmail.com
+380341595095	1982	Kasandra	Dibbert	Aliza_Schowalter98@hotmail.com
+380344108906	1603	Otto	Brown	Vinnie70@yahoo.com
+380344145249	1851	Geo	Shields	Frieda.Koch@hotmail.com
+380344740233	1737	Janessa	Schulist	Isac34@hotmail.com
+380344904140	1509	Priscilla	Bahringer	Nat18@yahoo.com
+380344922647	1752	German	West	Darby_Blanda17@gmail.com
+380345389424	1707	Noemie	Padberg	Shannon_Effertz81@yahoo.com
+380345669443	1746	Marge	Murazik	Antonetta.Gerlach@hotmail.com
+380345910040	1864	Seth	O'Keefe	Raymond.Maggio19@gmail.com
+380347318735	1743	Elyssa	Denesik	Napoleon_Hermiston@gmail.com
+380347838211	1566	Penelope	Johnson	Lacy.Considine@hotmail.com
+380348007042	1728	Nestor	Lang	Grover_Thiel67@gmail.com
+380348008062	1734	Gregorio	Kunde	Marvin95@gmail.com
+380349330957	1646	Alvis	Gleichner	Twila81@yahoo.com
+380349377957	1815	Alanna	Schimmel	Meggie_Ziemann@yahoo.com
+380350272278	1757	Filiberto	Champlin	Milo.Green@gmail.com
+380350721189	1975	Amely	Hessel	Bruce.Nienow@yahoo.com
+380350827845	1698	Jasmin	Terry	Elvie_Harvey@gmail.com
+380350912967	1678	Wilfred	Hoeger	Levi82@gmail.com
+380351444024	1933	Sam	Schmidt	Tristian.Lemke45@gmail.com
+380352888263	1905	Hayden	Will	Mohammed_Kerluke18@gmail.com
+380353768999	1537	Wilbert	Padberg	Reinhold.Bergstrom28@yahoo.com
+380353779966	1924	Elenora	Franecki	Margarett_Cassin@gmail.com
+380353987610	1987	Nestor	Rippin	Casandra_Johns11@hotmail.com
+380353995793	1684	Ernest	Gleichner	Liana.Mayert@yahoo.com
+380354097906	1786	Erin	Howell	Hazel_Ziemann51@yahoo.com
+380354388770	1807	Charlie	Murazik	Mckayla.Frami50@yahoo.com
+380355827503	1598	Lenna	Feest	Giovanna_Rippin@hotmail.com
+380357242961	1794	Sabina	Corkery	Javier4@gmail.com
+380358116898	1992	Stewart	Gaylord	Rupert_Legros@gmail.com
+380358236687	1861	Cecile	Kertzmann	Kacey_Brown@hotmail.com
+380359889004	1629	Zakary	Walsh	Ryan_Waters@yahoo.com
+380361087412	1851	Shakira	Jenkins	Vella.Spinka50@yahoo.com
+380362708363	1768	Carey	Sporer	Dayana56@yahoo.com
+380363519306	1553	Buddy	Schuster	Jewel36@gmail.com
+380363555362	1828	Moriah	Murazik	Stacey.Wuckert@gmail.com
+380363927925	1924	Ardith	Runolfsdottir	Lora58@gmail.com
+380364235413	1941	Arlene	Nolan	Braden_OKon@hotmail.com
+380364997432	1960	Felipe	Wyman	Brenna_Halvorson@hotmail.com
+380366153673	1763	Alexandra	Trantow	Verda68@hotmail.com
+380366886354	1517	Boyd	Ondricka	Austin99@hotmail.com
+380367466104	1790	Reggie	Lindgren	Jayme_Kutch@yahoo.com
+380367609338	1552	Zelda	Denesik	Carmen.Corwin7@gmail.com
+380368002628	1973	Fritz	Schaefer	Krystel_Lowe24@yahoo.com
+380369500155	1817	Merritt	Abernathy	Gerardo.Wisoky@gmail.com
+380369901579	1674	Anais	Erdman	Vita.Nolan75@gmail.com
+380370408000	1995	Orin	Labadie	Jordon7@gmail.com
+380370455834	1881	Coby	Medhurst	Jayne53@hotmail.com
+380372221507	1667	Aubrey	Ernser	Verdie_Johnson@gmail.com
+380372299913	1640	Gertrude	Heidenreich	Dashawn17@hotmail.com
+380372960711	1654	Carole	Gibson	Vicente_Bins18@yahoo.com
+380373205623	1726	Danyka	Towne	Loraine.Smitham@hotmail.com
+380374020433	1616	Aiyana	Flatley	Athena.Kuhic@gmail.com
+380374530801	1734	Renee	Friesen	Gerard.Kohler@gmail.com
+380375233710	1848	Sofia	Torphy	Ellie_Stark32@hotmail.com
+380376963270	1819	Delphia	Treutel	Eloisa37@gmail.com
+380377603044	1678	Rahsaan	Sawayn	Adolphus27@gmail.com
+380378229012	1836	Lionel	Deckow	Myrtie81@yahoo.com
+380379887118	1867	Martin	McGlynn	Weldon.Dach@hotmail.com
+380379967396	1731	Thora	Williamson	Josie.Kunze88@yahoo.com
+380380052097	1833	Furman	Hane	Domingo55@gmail.com
+380383316304	1597	Wallace	Block	Susana_Strosin47@yahoo.com
+380387135372	1704	Janiya	Satterfield	Chanelle_Johnston@hotmail.com
+380387923334	1753	Cyrus	Paucek	Pete_Bogisich49@hotmail.com
+380387933093	1990	Domenico	Weissnat	Molly81@gmail.com
+380388410118	1947	Rylee	Cassin	Roderick.Lesch75@hotmail.com
+380388928271	1576	Hudson	Hyatt	Maye78@yahoo.com
+380389234236	1992	Granville	Blick	Clyde.Botsford@gmail.com
+380390459850	1572	Adonis	Crona	Rocky.Jacobson9@yahoo.com
+380391038075	1523	Natalie	Schiller	Berry.Kozey28@yahoo.com
+380391243678	1722	Hayden	Lockman	Fleta_Maggio@yahoo.com
+380391325631	1633	Kyleigh	Tromp	Vada_Leffler@gmail.com
+380391507074	1639	Fred	Kerluke	Juwan27@yahoo.com
+380391751994	1979	Unique	Fahey	Sabryna13@yahoo.com
+380392536256	1842	Demario	Murray	Summer.Corkery20@gmail.com
+380393452332	1576	Burdette	Torphy	Noemie.Spinka78@gmail.com
+380393998493	1844	Kaden	Weimann	Chadrick_Bode@yahoo.com
+380394995744	1610	Judy	Franecki	Fleta32@yahoo.com
+380395299999	1575	Jeramie	Grant	Madelyn_Pfannerstill@hotmail.com
+380395316525	1915	Aurelie	Schroeder	Stevie36@yahoo.com
+380396090153	1783	Carmelo	Gaylord	Christ_Schuster12@gmail.com
+380397940352	1881	Hettie	Waters	Layne73@gmail.com
+380399070934	1756	Florian	Orn	Johathan35@hotmail.com
+380400302175	1807	Torrey	Schuppe	Peter.Moore77@gmail.com
+380400478633	1651	Llewellyn	Botsford	Nona_Boyle92@yahoo.com
+380401684163	1813	Alejandrin	Wuckert	Marquis_Bode66@hotmail.com
+380402222723	1910	Hollie	Hilpert	Salma38@yahoo.com
+380402502999	1637	Andre	Jast	Armando_Tromp2@yahoo.com
+380405153923	1773	Jaycee	Boehm	Jarret_Langosh@yahoo.com
+380405242601	1544	Jaquan	Bogisich	Eudora_Weissnat@yahoo.com
+380406701349	1823	Macey	Bode	Landen.Becker48@hotmail.com
+380406807239	1706	Shana	Durgan	Carmela.Bruen28@hotmail.com
+380408164379	1637	Everardo	Jakubowski	Porter8@gmail.com
+380408395432	1671	Kenton	Toy	Salvador25@hotmail.com
+380410314994	1662	Elisa	Fisher	Triston_Roob43@yahoo.com
+380412205228	1819	Ola	Okuneva	Mckenzie.Spencer@gmail.com
+380413293739	1959	Declan	Lemke	Raquel.Fay@hotmail.com
+380413921408	1744	Donna	Kihn	Westley25@gmail.com
+380414432334	1749	Holly	Predovic	Waldo_Lynch8@gmail.com
+380415413782	1719	Colby	Romaguera	Fletcher77@hotmail.com
+380415637735	1758	Meaghan	VonRueden	Dejah_Moen@yahoo.com
+380416858334	2001	Elias	Jacobson	Clementina.Sanford@yahoo.com
+380417830929	1652	Aimee	Langworth	Jannie_Orn98@hotmail.com
+380418813019	1846	Guadalupe	Leannon	Chesley83@yahoo.com
+380418834923	1562	Alford	Kautzer	Marianna46@hotmail.com
+380418906678	1593	Vanessa	Bahringer	Alexandro38@yahoo.com
+380418999050	1537	Leann	Witting	Luther64@hotmail.com
+380419222035	1980	Elnora	Monahan	Lafayette_Block@yahoo.com
+380420675645	1968	Aron	Pollich	Oliver.Stanton14@hotmail.com
+380421549515	1844	Giuseppe	Weber	Marcelle.OKon@gmail.com
+380421947153	1806	Giles	Hoeger	Robyn.Altenwerth76@gmail.com
+380423412653	1838	Florida	Fritsch	Corrine14@yahoo.com
+380423591805	1564	Velma	Christiansen	Lola60@yahoo.com
+380426102672	1737	Dorothea	Larkin	Abner_Greenfelder@yahoo.com
+380426534210	1737	Dwight	Stroman	Darron88@hotmail.com
+380427439045	1811	Monserrat	Funk	Everardo.Carroll24@yahoo.com
+380428716882	1679	William	Waters	Stella15@hotmail.com
+380428964690	1913	Jabari	Nicolas	Cody_Wuckert50@hotmail.com
+380429933419	1711	Caroline	Friesen	Axel.Corwin39@yahoo.com
+380431517396	1917	Norberto	Sipes	Madyson_Huels18@hotmail.com
+380431660856	1707	Sarai	Sawayn	Kristina_Pfannerstill@yahoo.com
+380431808886	1807	Brandon	Zemlak	Alyce.Pacocha90@hotmail.com
+380432448449	1599	Kasandra	Kiehn	Anastacio.Abshire50@yahoo.com
+380432926145	1983	Alia	Bartoletti	Aletha.Doyle@yahoo.com
+380433003837	1607	Maudie	McDermott	Ceasar_Cronin38@gmail.com
+380433879056	1898	Chris	Koch	Agustin94@gmail.com
+380434742775	1945	Jody	Wilkinson	Veda.Mayer@hotmail.com
+380435006551	1836	Nico	Pagac	Cassidy50@gmail.com
+380435431603	1883	Gladys	Daugherty	Lonny_Walter@gmail.com
+380435724037	1561	Garret	Fahey	Megane28@yahoo.com
+380437270872	1988	Brain	Paucek	Kallie53@yahoo.com
+380437838309	1581	Ray	Hammes	Helena_Zemlak46@gmail.com
+380438405407	1816	Orpha	Mueller	Leif.Tremblay75@yahoo.com
+380439140267	1780	Emmanuelle	Crooks	Gillian8@gmail.com
+380439461471	1906	Yasmin	Johns	Aiyana_Adams@yahoo.com
+380441390694	1764	Jaquelin	Jakubowski	Alexandro.Heidenreich55@gmail.com
+380442026308	1607	Conner	Ankunding	Stan7@yahoo.com
+380442170799	1558	Jimmy	Mills	Esmeralda.Rippin@yahoo.com
+380442559364	1995	Eva	Rowe	Dayne.Kling11@hotmail.com
+380442856569	1747	Fatima	Hauck	Earlene.Abbott@gmail.com
+380443882387	1869	Kiarra	Hodkiewicz	Vicenta32@hotmail.com
+380443905006	1579	Juwan	Hermiston	Jamaal_Veum80@hotmail.com
+380444080150	1789	Nayeli	Pagac	Keeley_Kshlerin@gmail.com
+380445734701	1574	Chaya	Marquardt	Milton33@gmail.com
+380447169956	1686	Justice	Stamm	Mary_Mayert24@yahoo.com
+380447304160	1787	Marisa	Weber	Keara.Schuster@gmail.com
+380448088652	1751	Hailee	Lockman	Trisha17@yahoo.com
+380448866677	1929	Angelo	Dicki	Alanna95@gmail.com
+380450239788	1771	Sophie	Roob	Jerald_Frami@hotmail.com
+380450248818	1765	Ervin	Braun	Ozella34@gmail.com
+380452260764	1976	Cassie	Johnson	Elmer50@yahoo.com
+380453273761	1930	Valentine	Greenholt	Brooks.Crist@gmail.com
+380453520842	1742	Kaylee	Von	Hollis.Stanton65@hotmail.com
+380454273445	1992	Emmy	Kemmer	Larry.Schmidt@gmail.com
+380454734735	1693	Julianne	Schuppe	Billie76@yahoo.com
+380454979630	1907	Shemar	Kub	Karolann_Lynch49@yahoo.com
+380455275510	1997	Charlie	Berge	Warren71@gmail.com
+380457950779	1724	Steve	Kovacek	Isabel_Heidenreich96@yahoo.com
+380459100374	1968	Mae	O'Keefe	Bonita.Jenkins62@yahoo.com
+380459980523	1875	Lee	Schimmel	Timothy83@yahoo.com
+380460194215	1880	Ethelyn	Wolf	Nathan18@gmail.com
+380460454820	1993	Dejah	Abshire	Stewart_Toy@gmail.com
+380460641550	1781	Rosetta	Fadel	Katrine_Mayer@gmail.com
+380460859950	1592	Edgardo	Carroll	Myles.Botsford68@yahoo.com
+380460999824	1815	Arden	Schmitt	Jamil.Weissnat5@hotmail.com
+380461246507	1648	Nettie	Hermiston	Aubrey.Smitham@yahoo.com
+380465085902	1578	Ladarius	Ortiz	Alda_Gerhold@gmail.com
+380465148473	1932	Krystal	Turcotte	Adela.Spencer@gmail.com
+380465282892	1671	Koby	Monahan	Savanah.Abernathy@hotmail.com
+380465448044	1667	Cindy	Ortiz	Edwina_Erdman33@gmail.com
+380465732311	1776	Magdalen	Kohler	Hertha55@yahoo.com
+380465920079	1577	Zechariah	Gerlach	Damaris_Gleichner@gmail.com
+380466514362	1852	Tanya	Crist	Katrine_Wiza69@yahoo.com
+380467370475	1622	Noemi	Olson	Grover.Wolf@yahoo.com
+380470406120	1835	Madyson	Fisher	Elmira.Goodwin4@yahoo.com
+380472025479	1949	Ova	Skiles	Levi.Wilderman57@gmail.com
+380472250124	1960	Christ	Abbott	Murphy_Daugherty@hotmail.com
+380473864447	1571	Danyka	Murazik	Llewellyn_Gaylord@gmail.com
+380474121840	1741	Wilber	Kerluke	Dennis_Abernathy@yahoo.com
+380474972934	1575	Marshall	Abbott	Harold.Lebsack@gmail.com
+380476432234	1546	Nikolas	Hackett	Harry42@gmail.com
+380476778122	1865	Kavon	Kuphal	Stefan.Bartoletti47@gmail.com
+380478329481	1761	Amya	Boyle	Gardner_Lubowitz23@hotmail.com
+380478634453	1907	Larue	Brekke	Savanna.OHara41@gmail.com
+380478895130	1621	Charity	Nitzsche	Bettie_Walter@hotmail.com
+380479280351	1613	Destany	Cummerata	Aimee45@gmail.com
+380480535072	1940	Mallie	Thiel	Benton.Heller@yahoo.com
+380482822106	1509	Tracy	McClure	Logan15@gmail.com
+380482989462	1755	Creola	Robel	Josiane50@hotmail.com
+380484224481	1509	Jeanie	Gaylord	Uriel14@yahoo.com
+380485105847	1828	Khalil	Cummings	Laurence.Schultz15@hotmail.com
+380485318949	1771	Lesley	Lebsack	Karine_Cartwright31@gmail.com
+380486908504	1696	Ambrose	Bins	Sid.Willms47@hotmail.com
+380487304224	1887	Raymond	Berge	Sarai.Runolfsdottir@yahoo.com
+380488193234	1894	Keyon	Grimes	Easter34@hotmail.com
+380489885886	1834	Porter	Fadel	Johnathon_Lowe@gmail.com
+380491759765	1630	Rhett	Kshlerin	Kelvin.Dicki@yahoo.com
+380493457316	1552	Prudence	Hartmann	Domenico1@hotmail.com
+380493828503	1892	Andre	McGlynn	Ebony_Hodkiewicz@yahoo.com
+380493945121	1975	Israel	Dicki	Lura7@hotmail.com
+380494964694	1950	Waldo	Bogan	Kaelyn.Green@yahoo.com
+380494989749	1856	Odie	Lind	Laney78@gmail.com
+380495315812	1848	Tania	Kulas	Lois_Graham68@hotmail.com
+380496785145	1519	Clifford	Prohaska	Sam.Leannon93@yahoo.com
+380497557223	1738	Saige	Senger	Anahi.Schulist92@hotmail.com
+380497741108	1786	Vernon	Hudson	Rodger97@hotmail.com
+380498244983	1663	Oceane	Feest	Antonetta93@gmail.com
+380499654181	1834	Lelah	O'Kon	Wilma.Marvin@hotmail.com
+380500256253	1946	Antone	Barton	Johnathan63@hotmail.com
+380500423266	1544	Edd	Auer	Gideon13@gmail.com
+380500467972	1876	Aleen	Waelchi	Aileen.Connelly@hotmail.com
+380501291021	1963	Russel	Boyle	Pietro_Grady@gmail.com
+380501600513	1741	Alvis	Kub	Louie_Pouros66@yahoo.com
+380503691965	1580	Heidi	Toy	Hanna.Oberbrunner@gmail.com
+380503924897	1689	Lexi	Durgan	Lois75@hotmail.com
+380506120292	1694	Kory	Lowe	Alize6@yahoo.com
+380506730446	1714	Ezekiel	Maggio	Mayra_Reynolds@yahoo.com
+380507575638	1837	Lilly	Sawayn	Kailey.Nader38@gmail.com
+380507688040	1939	Damaris	Smith	Dedric30@hotmail.com
+380508748071	1924	Milton	Hyatt	Enid52@gmail.com
+380508890494	1771	Penelope	Vandervort	Dominic56@hotmail.com
+380509050904	1595	Antonette	Dibbert	Allie96@gmail.com
+380509420968	1502	Olin	Koss	Kiara_Champlin22@gmail.com
+380510179543	1898	Tianna	Kohler	Leif_Beahan48@gmail.com
+380510456645	1783	Maynard	Carter	Kyra.Considine@hotmail.com
+380511104386	1820	Jayme	Dietrich	Anastasia_Weissnat60@gmail.com
+380511918599	1533	Margarita	Tillman	Fredrick14@yahoo.com
+380513341490	1743	Pablo	Muller	Walter_Price75@hotmail.com
+380513627794	1597	Vernie	Hirthe	Elda_Moen@yahoo.com
+380515329628	1797	Eric	Wintheiser	Leopold54@yahoo.com
+380516148852	1777	Norval	Heathcote	Eldora.Klein@hotmail.com
+380516313938	1811	Briana	Bashirian	Ismael_Adams93@gmail.com
+380516493394	1639	Judge	Jacobi	Eric.Klocko98@yahoo.com
+380516622318	1619	Orval	Orn	Oma.MacGyver@hotmail.com
+380516833964	1702	Christa	Larson	Enid_OConner0@hotmail.com
+380516958252	1560	Keegan	Hermiston	Iva_Weber70@yahoo.com
+380518676048	1539	Gaylord	Hyatt	Tristin.Lynch14@hotmail.com
+380519029781	1794	Deontae	Grady	Annabell.Luettgen@hotmail.com
+380519422918	1777	Christa	Douglas	Rogelio.Ritchie@yahoo.com
+380520023396	1993	Aaron	Kulas	Eddie_Mraz@gmail.com
+380521000326	1685	Michael	Wiza	Karianne9@gmail.com
+380521377145	1908	Rupert	Toy	Warren_Kuhic80@hotmail.com
+380523035789	1813	Merl	Bergstrom	Tania_Wisoky94@gmail.com
+380523222427	1597	Lacy	Mohr	Zola.Swaniawski52@hotmail.com
+380523308132	1819	Adaline	Nicolas	Ofelia46@yahoo.com
+380524910807	1765	Rudy	Schultz	Niko.Lockman96@yahoo.com
+380524954048	1673	Dianna	Wuckert	Marcus.Lebsack69@hotmail.com
+380524970976	1918	Forest	Deckow	Shawna_Kutch@hotmail.com
+380526750737	1540	Declan	Schroeder	Odell24@hotmail.com
+380527116051	1761	Annie	Jakubowski	Kaitlyn95@gmail.com
+380527870605	1862	Ryder	Ferry	Herta83@hotmail.com
+380528543796	1539	Friedrich	Considine	Merle.Zemlak@hotmail.com
+380529695999	1550	Morgan	Pfannerstill	Adonis_Zboncak@gmail.com
+380530614125	1744	Demetrius	Okuneva	Delilah.Emmerich31@gmail.com
+380530832147	1990	Laverne	Kessler	Keven_Predovic49@hotmail.com
+380532376495	1634	Mittie	Orn	Hiram.Swift@gmail.com
+380533088211	1583	Nella	Schmitt	Marlene.Morissette97@yahoo.com
+380533422465	1845	Juanita	Gerhold	Michaela_Deckow44@yahoo.com
+380533455729	1603	Wilbert	Runte	Mckenzie_Kuhic@gmail.com
+380533524782	1965	Aracely	McKenzie	Tyra5@hotmail.com
+380533810245	1975	Catalina	Mante	Roselyn_Simonis@hotmail.com
+380534022692	1910	Bernice	Renner	Savannah_Bernier63@hotmail.com
+380534226500	1702	Richie	Smith	Jadyn_Treutel18@yahoo.com
+380534347900	1978	Ramona	Walker	Cortney_Abernathy@gmail.com
+380535118206	1843	Jolie	Bartell	Meda_Schumm@hotmail.com
+380535591680	1593	Nathanial	Crooks	Lafayette.Cruickshank27@yahoo.com
+380538080405	1624	Kaitlyn	Pollich	Maya_DAmore@yahoo.com
+380538308603	1911	Nelle	Schmitt	Augusta.Herman78@hotmail.com
+380538574174	1705	Tiara	Gibson	Danielle4@gmail.com
+380539155157	1723	Herminia	Denesik	Fleta_Paucek3@yahoo.com
+380539741823	1900	Noelia	Bailey	Jovanny_Purdy@gmail.com
+380540154416	1590	Chasity	Nikolaus	Albin2@yahoo.com
+380541438149	1580	Ezekiel	Kassulke	Anne_Rempel27@gmail.com
+380542287533	1543	Eric	Kovacek	Brice.Jacobs47@gmail.com
+380542614825	1836	Gregorio	Adams	Luciano.Koss11@hotmail.com
+380543171787	1651	Horacio	Bechtelar	Kristoffer.Senger22@yahoo.com
+380543578362	1867	Kip	Rice	Abner63@gmail.com
+380543604067	1970	Vidal	Grant	Juwan_Kautzer@yahoo.com
+380544178527	1985	Serenity	Waelchi	Bradford.Berge@yahoo.com
+380546686040	1650	Devon	Botsford	Barrett49@hotmail.com
+380547315717	1735	Neal	Thompson	Gonzalo_Leffler60@gmail.com
+380549526917	1745	Leonie	Klein	Chelsey_Pollich@hotmail.com
+380550463877	1974	Holden	Collins	Vince.Herman@yahoo.com
+380553053008	1549	Bart	Veum	Jaiden32@gmail.com
+380553496559	1619	Dorothea	Spinka	Dejon.Ritchie@yahoo.com
+380554367328	1527	Wilford	Nienow	Reggie_Goyette67@yahoo.com
+380554475982	1511	Jonathan	Langworth	Ike_Murphy73@yahoo.com
+380554566142	1715	Sibyl	Borer	Simone80@gmail.com
+380554779851	1831	Asa	Mitchell	Gladyce95@hotmail.com
+380554781090	1911	Milford	Goodwin	Ettie26@gmail.com
+380554850271	1986	Tyson	Wyman	Elisha89@yahoo.com
+380555262953	1740	Katrine	Stracke	Abbey_Schamberger76@hotmail.com
+380555900840	1911	Darby	Pouros	Jacinthe_Jacobson58@gmail.com
+380557578147	1684	Shanel	Kuhlman	Hayden.Weimann69@yahoo.com
+380558948338	1753	Jackeline	O'Connell	Deshaun.Schulist@yahoo.com
+380559381952	1578	Marisa	Sauer	Ila_Rippin@yahoo.com
+380559384790	1640	Clara	Connelly	Marques76@hotmail.com
+380562367880	1699	Elissa	Johns	Barry_Beatty@hotmail.com
+380564816346	1873	Lukas	Runolfsson	Jarret_Fisher@hotmail.com
+380565692401	1974	Lizeth	Stark	Ronny.Leannon20@yahoo.com
+380566208359	1657	Aurelio	Crist	Kirstin.Huel87@gmail.com
+380566856657	1919	Oswald	Jaskolski	Veronica76@hotmail.com
+380567406759	1688	Dessie	Kuhic	Chaim_Adams@hotmail.com
+380567697835	1761	Carmelo	Gutkowski	Alanis6@yahoo.com
+380567704321	1974	Jarvis	Stracke	Jameson93@hotmail.com
+380002546095	1702	Elta	Hickle	\N
+380567889344	1654	Clemmie	Brakus	Jonathan11@hotmail.com
+380568196655	1530	Theo	Kunze	Dedrick_Dicki@yahoo.com
+380568312544	1866	Delphine	Schaden	Lurline99@gmail.com
+380568351210	1994	Roger	Reilly	Maximillia23@yahoo.com
+380569041840	1629	Jude	Wunsch	Narciso96@yahoo.com
+380569410247	1877	Destini	Harvey	Mackenzie_Rodriguez86@gmail.com
+380569601933	1589	Mozelle	Bogan	Margarett.Rippin@hotmail.com
+380570357685	1774	Helen	Oberbrunner	Joany.Nader@yahoo.com
+380572814004	1591	Hannah	Kuhic	Kenna.Marvin@hotmail.com
+380573614373	1518	Lafayette	Spencer	Brant.Labadie@yahoo.com
+380573632203	1534	Delores	Rutherford	Kurt_Predovic58@hotmail.com
+380574134868	1771	Jonathan	Skiles	Jane39@yahoo.com
+380574558002	1729	Shawn	Yost	Carrie_Hilpert@yahoo.com
+380574606149	1762	Emilio	Nicolas	Paula.Marvin@yahoo.com
+380574707509	1858	Finn	Schimmel	Jennie_Lubowitz12@gmail.com
+380575067003	1991	Chaya	Ritchie	Elwin_Bednar7@yahoo.com
+380575628980	1620	Layne	Thiel	Buck_Spinka@yahoo.com
+380576679760	1855	Vicky	Casper	Triston_Kiehn@hotmail.com
+380576902872	1728	Nicole	Mitchell	Sheridan.Rau@hotmail.com
+380576991378	1639	Kali	Schumm	Elisha_Wilkinson@yahoo.com
+380577019139	1795	Magdalen	Hermiston	Golda.Heller@gmail.com
+380578218190	1850	Dallas	Schultz	Candido_Moen29@gmail.com
+380578573088	1947	Alvena	Kovacek	Alejandra53@gmail.com
+380578781267	1785	Era	Bartoletti	Domenic21@yahoo.com
+380578914964	1517	Elena	Macejkovic	Sterling_Donnelly39@yahoo.com
+380579399258	1617	Reginald	Reichert	Lexi97@hotmail.com
+380580401438	1693	Gerson	Sipes	Kobe_Langosh54@yahoo.com
+380580603311	1727	Jerad	Russel	Casey_Lubowitz70@hotmail.com
+380580639248	1926	Henriette	Prosacco	Wilber_Schmidt91@yahoo.com
+380581615973	1774	Dariana	Weber	Pietro_Stanton73@gmail.com
+380581848535	1935	Aric	Ratke	Madalyn_Von39@yahoo.com
+380581871828	1589	Verlie	Green	Walter.Ebert72@yahoo.com
+380582554695	1845	Lillian	Cartwright	Forrest90@yahoo.com
+380583151063	1524	Otilia	Kautzer	Margaret.Homenick@hotmail.com
+380583472969	1880	Lionel	Kovacek	Aileen_Daugherty@hotmail.com
+380584495691	1670	Trinity	Beatty	Coty38@yahoo.com
+380585297393	1594	Juanita	Langosh	Terrell26@hotmail.com
+380585789863	1964	Laurence	Leffler	Summer.McLaughlin@hotmail.com
+380585818647	1975	Verner	Parisian	Guiseppe.Trantow@hotmail.com
+380586202768	1675	Stuart	White	Zita_Connelly@gmail.com
+380586218792	1644	Neha	Abshire	Ahmed_Reichel@hotmail.com
+380586826905	1708	Lowell	Schoen	Lucile.Turcotte4@gmail.com
+380587034345	1787	Candace	Doyle	Phyllis_Bahringer@hotmail.com
+380588570985	1862	Celestino	Raynor	Marco58@gmail.com
+380588848617	1635	Arthur	Wisozk	Prudence.Little@hotmail.com
+380591177571	1601	Melisa	Bartell	Osvaldo_Grant@hotmail.com
+380591438907	1567	Ali	Anderson	Adolph48@hotmail.com
+380591899243	1826	Destini	Schiller	Dylan_Welch24@gmail.com
+380591994950	1826	Jaylon	Powlowski	Theresa_Oberbrunner@gmail.com
+380592060258	1541	Casper	Brakus	Mauricio25@hotmail.com
+380593164897	1648	Jettie	Turcotte	Irving_Tromp@hotmail.com
+380593592077	1652	Johnnie	O'Connell	Tracey_Willms35@hotmail.com
+380594460273	1635	Merle	Kuvalis	Leo.Wilkinson@gmail.com
+380595793883	1519	Dejuan	Roob	Lincoln.Dietrich@hotmail.com
+380596791106	1871	Prince	Glover	Queen11@yahoo.com
+380597193164	1968	Misael	Kuhic	Kira46@gmail.com
+380597318434	1695	Mylene	Corkery	Lora43@hotmail.com
+380597580146	1714	Vanessa	Mertz	Johnnie_Ankunding20@hotmail.com
+380597790886	1724	Jada	Braun	Rosalee_Harber60@gmail.com
+380597815106	1854	Jeff	Lang	Rossie_Predovic@hotmail.com
+380600481632	1735	Ora	Brakus	Dominique.Streich41@hotmail.com
+380601167518	1904	Cameron	Rippin	Maybell65@hotmail.com
+380601401966	1553	Matilda	Heidenreich	Joyce_Oberbrunner33@hotmail.com
+380602333538	1825	Itzel	Skiles	Hellen_Jacobs61@hotmail.com
+380602400182	1793	Edmond	Hirthe	Laurence90@hotmail.com
+380602649326	1584	Raphael	Heidenreich	Kale0@gmail.com
+380604834533	1694	Adrianna	Gerhold	Keira.Marquardt@hotmail.com
+380606129041	1894	Brooklyn	Walter	Macie.Larkin@gmail.com
+380606272487	1852	Randi	McGlynn	Major_Bogan54@gmail.com
+380606476175	1930	Kristoffer	Lakin	Margret.Barton81@hotmail.com
+380607111301	1999	Abdul	Gerhold	Danial.Terry65@gmail.com
+380607954687	1807	Jeffrey	Goodwin	Joaquin66@gmail.com
+380608589958	1597	Ottilie	Price	Daryl_Kling@gmail.com
+380611830453	1678	Orpha	Greenfelder	Oran61@gmail.com
+380611928343	1507	Ines	Gibson	Bartholome.McLaughlin@gmail.com
+380612082002	1897	Dorthy	Veum	Marlene.Donnelly61@yahoo.com
+380612988676	1802	Kevon	Reilly	Brycen_Miller87@yahoo.com
+380614437795	1720	Caesar	Kuphal	Dudley_Marvin@gmail.com
+380614610146	1986	Samara	Glover	Viviane46@hotmail.com
+380615563475	1672	Emanuel	Quitzon	Avis_Considine60@yahoo.com
+380615607204	1681	Osvaldo	Roob	Mertie_Gleichner9@yahoo.com
+380615717494	1932	Laverna	Prosacco	Ricky1@hotmail.com
+380615878104	1835	Akeem	Armstrong	Davon.Denesik@yahoo.com
+380616165158	1568	Anais	Sawayn	Hardy.Morar98@yahoo.com
+380616265071	1595	Berniece	Kohler	Felipe.Will@gmail.com
+380616745413	1749	Obie	Medhurst	Katlyn.Mills66@yahoo.com
+380617117083	1861	Sydnie	Reilly	Deonte_Walter@gmail.com
+380617512905	1964	Aileen	Robel	Adolph.Leffler@hotmail.com
+380617989751	1988	Arvel	Shields	Michaela.Wehner@gmail.com
+380618020741	1965	Lysanne	Rice	Ayden56@yahoo.com
+380618031931	1605	Madalyn	Cremin	Agnes.Terry@hotmail.com
+380618542851	1940	Marilyne	Larson	Cielo_Raynor72@yahoo.com
+380618609992	1521	Douglas	Weber	Chaz.Luettgen@gmail.com
+380620137078	1925	Loraine	Bayer	Devon.Hilpert90@hotmail.com
+380620225050	1812	Roman	Bednar	Lorena56@gmail.com
+380620880850	1798	Ofelia	Kuvalis	Everardo67@hotmail.com
+380622084892	1773	Rossie	Cassin	Berniece36@gmail.com
+380622967750	1816	Natalia	Abshire	Caleb_Zulauf83@hotmail.com
+380623696250	1708	Nikolas	Bayer	Edmund52@gmail.com
+380624676473	1789	Vanessa	Langosh	Zane.Renner@hotmail.com
+380625168742	1845	Adolph	Legros	Eva.Friesen@yahoo.com
+380626430431	1707	Ryan	Schowalter	Yoshiko78@hotmail.com
+380627102664	1741	Liliana	Veum	Melvina.McKenzie@hotmail.com
+380627282592	1587	Brett	Goodwin	Florence36@hotmail.com
+380627353767	1722	Elliott	Cremin	Darrin_Stiedemann@gmail.com
+380627564049	1769	Leslie	Beer	Anabelle.Dickinson@gmail.com
+380627566638	1569	Tristin	Ritchie	Muriel_Kohler19@hotmail.com
+380627574456	1556	Zander	Gottlieb	Aylin8@gmail.com
+380627658490	1651	Laurence	Bogan	Emerald_Beer@hotmail.com
+380627750942	1774	Toney	Ruecker	Lawson17@gmail.com
+380628039718	1978	Jay	Larkin	Elsa.Mayer42@hotmail.com
+380628624316	1655	Pink	Ward	Ahmad.Murazik11@gmail.com
+380628640723	1525	Brayan	Abernathy	Raphaelle_Kling94@yahoo.com
+380629244238	1702	Dewitt	Schumm	Gina34@yahoo.com
+380629524411	1987	Jarrett	Quigley	Joanne.Bernier87@hotmail.com
+380631332045	1906	Kaylee	Feest	Rickey_Kohler@gmail.com
+380632576339	1761	Damaris	Halvorson	Alfredo7@gmail.com
+380633231782	1545	Darron	Gibson	Marcelina_Balistreri58@yahoo.com
+380633638743	1835	Krystel	Swift	Clarabelle.Russel@hotmail.com
+380633781276	1744	Frieda	Huel	Cordell55@yahoo.com
+380635772845	1655	Quinten	Connelly	Morris_Beer@gmail.com
+380636162557	1701	Halle	Von	Haven_Kuphal96@hotmail.com
+380636347137	1581	Jonathan	Weissnat	Gwendolyn.Pfannerstill@gmail.com
+380636741235	1545	Hazel	Rath	Shanny32@yahoo.com
+380637192739	1763	Tatum	Ankunding	Eduardo33@hotmail.com
+380637217206	1774	Maybelle	Botsford	Ralph.Lebsack97@yahoo.com
+380637476655	1795	Odell	Turner	Enos.Quigley@yahoo.com
+380638047846	1937	Jettie	Weissnat	Walton_Steuber6@gmail.com
+380639903857	1835	Damion	Kulas	Raoul.Flatley@gmail.com
+380640279089	1687	Alfred	Price	Jodie.Schuster75@yahoo.com
+380640311748	1796	Yoshiko	Gleason	Willa_Bergstrom79@hotmail.com
+380640791691	1650	Robin	Rippin	Deon14@hotmail.com
+380640954557	1561	Stone	Goldner	Cyrus_McCullough97@yahoo.com
+380642220522	1934	Durward	Dooley	Dallin_Wisozk@hotmail.com
+380642624885	1864	Travis	Kozey	Tess_Trantow12@gmail.com
+380642817268	1911	Maggie	Wilkinson	Alejandrin.Buckridge@yahoo.com
+380643677390	1743	Jody	Rolfson	Ivy_Crist@yahoo.com
+380643721624	1652	Emie	Boehm	Dock_Bernhard@hotmail.com
+380645373089	1818	Vincent	Watsica	Evelyn8@gmail.com
+380646376843	1798	Marge	Baumbach	Marques.Reynolds63@gmail.com
+380647294271	1693	Bruce	Treutel	Cayla64@hotmail.com
+380648740088	1777	Karen	Tromp	Florian35@hotmail.com
+380649490344	1811	Henri	Greenfelder	Mike_Stoltenberg32@gmail.com
+380650821330	1828	Ephraim	Senger	Darwin.Ankunding32@gmail.com
+380651252659	1881	Maryam	Kuhn	Edmund_Kemmer17@hotmail.com
+380652312958	1925	Arnulfo	Hoppe	Name.Ratke@gmail.com
+380653515800	1773	Margaret	Lakin	Ettie_Luettgen94@hotmail.com
+380653784135	1981	Alisha	Mann	Trey24@yahoo.com
+380654507518	1638	Danielle	Labadie	Freida_Goldner99@gmail.com
+380654581214	1813	Beatrice	Schowalter	Cornell26@yahoo.com
+380656198525	1561	Noe	Bahringer	Shanelle_Runte13@gmail.com
+380656855607	1863	Justina	Wiegand	Mose86@hotmail.com
+380657972790	1546	Laney	Schamberger	Jaquan_Kunde94@hotmail.com
+380658106510	1973	Miracle	Kuhic	Alex44@hotmail.com
+380658641061	1804	Edgar	Walker	Kendall_Witting@yahoo.com
+380658930296	1701	Arvel	Armstrong	Pasquale_Stehr@gmail.com
+380659371877	1783	Zula	Runolfsdottir	Molly91@yahoo.com
+380659463084	1887	Dillon	Bradtke	Quincy_Johnston25@gmail.com
+380659469539	1507	Enrique	Dickinson	Pansy.OHara@gmail.com
+380659679454	1810	Mae	Mertz	Skyla_Ledner28@yahoo.com
+380660043840	1561	Barton	Altenwerth	Glennie_Murray@yahoo.com
+380660941655	1895	Kaelyn	Mohr	Nicolas_Reinger@yahoo.com
+380661377778	1677	Rosella	Abbott	Liliane87@hotmail.com
+380662071136	1747	Norene	Armstrong	Shyanne.Hickle1@yahoo.com
+380662103702	1904	Buster	Beer	Sam58@yahoo.com
+380662350643	1941	Jason	Bernhard	Simone_Stracke@hotmail.com
+380662558582	1973	River	Kohler	Sandrine66@gmail.com
+380663783631	1742	Hector	Price	Glenda_Wilkinson@gmail.com
+380663937563	1589	Adalberto	Blanda	Izaiah_Shanahan69@gmail.com
+380663981717	1856	Deanna	Skiles	Nakia.Lehner@yahoo.com
+380664189229	1625	Alec	Huel	Rupert_Yundt32@gmail.com
+380664908334	1614	Casey	Turner	Bernie21@gmail.com
+380665519108	1590	Helga	Skiles	Marcia_Quigley@hotmail.com
+380665961860	1692	Shanna	Prosacco	Vladimir_Collins@yahoo.com
+380666158505	1959	Kendrick	Funk	Duane_Goldner@yahoo.com
+380666883178	1797	Peter	Romaguera	Toy9@gmail.com
+380667518933	1888	Katrina	Littel	Rose.Mraz5@hotmail.com
+380667975364	1937	Devan	Moore	Markus_Rippin@yahoo.com
+380668589425	1712	Bryon	Harber	Rigoberto.Schoen6@gmail.com
+380669619233	1960	Selmer	Price	Deanna_Skiles74@hotmail.com
+380669939243	1574	Daren	Reinger	Gerardo.Stracke@gmail.com
+380672975313	1850	Donald	Altenwerth	Eulah.Keebler39@gmail.com
+380674035910	1764	Murl	Robel	Pinkie_Leffler@yahoo.com
+380674517871	1801	Magali	Shanahan	Spencer33@hotmail.com
+380676571377	1703	Lexie	Lehner	Sophie_Hand99@gmail.com
+380676854263	1782	Lila	Friesen	Amos.McClure21@hotmail.com
+380677111569	1578	Deonte	Hauck	Wendy_Gerhold1@hotmail.com
+380678399200	1966	Jessy	Bins	Llewellyn.Botsford42@hotmail.com
+380679807809	1669	Leora	Nikolaus	Edgardo.Weimann@gmail.com
+380680429347	1944	Unique	Romaguera	Chelsey.Batz19@yahoo.com
+380680704178	1574	Emery	Howell	Francis_Lowe66@gmail.com
+380681016112	1774	Stone	Schimmel	Danny28@gmail.com
+380681253352	1711	Shyann	Johnson	Retha.Goldner@yahoo.com
+380681554679	1921	Frederic	McClure	Rollin_Lindgren@hotmail.com
+380681555692	1900	Gaylord	Franecki	Deborah.Kilback@yahoo.com
+380681755990	1948	Hershel	McLaughlin	Elisa_Quigley20@hotmail.com
+380681783472	1615	Gino	Christiansen	Skylar.Mayert4@hotmail.com
+380682050690	1816	Karen	Reichel	Theresia_Langosh@gmail.com
+380682628756	1849	Erling	Torp	Lavonne24@gmail.com
+380682961092	1509	Art	Lesch	Martin_Mann@hotmail.com
+380684131500	1682	Cristian	Aufderhar	Gisselle_Hoppe77@hotmail.com
+380684330713	1963	Benjamin	Heller	Jeffry.Abernathy@yahoo.com
+380685198131	1874	Carson	Swift	Maryjane_Hoppe58@gmail.com
+380687576274	1987	Aryanna	Larson	Gavin.Dare@gmail.com
+380687706683	1942	Dee	DuBuque	Eino_Morissette37@yahoo.com
+380688027764	1740	Else	Connelly	Enola.Romaguera@hotmail.com
+380688854016	1918	Jacinto	Cronin	Leif59@gmail.com
+380689482994	1711	Eryn	Swaniawski	Eleazar_Kling49@yahoo.com
+380690579205	1818	Myles	Lemke	Mallory.King27@gmail.com
+380690842644	1658	Nicholas	Romaguera	Willow58@gmail.com
+380690989959	1588	Carmelo	Shanahan	Kimberly_Littel@yahoo.com
+380693425534	1944	Daphnee	Runte	David55@gmail.com
+380694172369	1819	Krystal	Bradtke	Lorine.OHara@yahoo.com
+380694759345	1832	Francis	Borer	Edmund_Rempel78@hotmail.com
+380694808011	1952	Zechariah	Cummings	Luis.McLaughlin@gmail.com
+380696387414	1961	Sierra	Dicki	Skyla.Kerluke73@yahoo.com
+380697740819	1601	Trenton	Gislason	Jaclyn_Botsford31@hotmail.com
+380698554974	1806	Karlie	Koelpin	Ransom_Smitham1@yahoo.com
+380699422484	1614	Shanelle	Grady	Mariam_Greenholt@yahoo.com
+380699453597	1570	Valentina	Koss	Loraine_Medhurst0@yahoo.com
+380701149750	1621	River	Yundt	Wilma.Ratke@gmail.com
+380701754519	1694	Elaina	Erdman	Emile_Schinner7@hotmail.com
+380702192226	1678	Savanna	Dicki	Stanley93@hotmail.com
+380702323272	2000	Arnoldo	Mayert	Stella_Beier33@hotmail.com
+380702333515	1917	Aileen	Bayer	Ruth_Cartwright@gmail.com
+380702686954	1631	Erica	Johns	Frederick.Abshire@yahoo.com
+380703601308	1921	Rory	Funk	Gay26@gmail.com
+380704450123	1526	Willy	Kub	Joshuah.Nitzsche14@hotmail.com
+380706096538	1790	Billie	Prohaska	Alexandra.Grimes87@yahoo.com
+380706829858	1840	Lelia	Beer	Laurine.Huels6@gmail.com
+380707046180	1607	Ross	Hessel	Robin.Schuster25@yahoo.com
+380707719142	1909	Chaim	Williamson	Amari47@yahoo.com
+380710115248	1936	Ransom	Gleichner	Tatum.Mayer@hotmail.com
+380711348639	1677	Nyasia	Satterfield	Kathryn76@yahoo.com
+380711641864	1814	Toney	Daugherty	Danial.Jones23@hotmail.com
+380711749748	1857	Tyreek	Bashirian	Eli_Rau@yahoo.com
+380712692936	1691	Gladyce	Reichert	Alysha_Schamberger@gmail.com
+380713360851	1805	Eleazar	Kautzer	Madilyn8@yahoo.com
+380714124967	1671	Rosendo	Gusikowski	Estrella.McGlynn@gmail.com
+380714126426	1931	Erika	Marquardt	Clyde35@yahoo.com
+380714140700	1638	Berta	Hamill	Dameon35@gmail.com
+380714164276	1915	Leonie	McKenzie	Annabell.Schimmel@gmail.com
+380714569330	1531	Brielle	Bechtelar	Una_Kunze@hotmail.com
+380714652815	1914	Loma	Spencer	Tina_Barton41@hotmail.com
+380714699599	1758	Chaya	Halvorson	Frances.Goldner@gmail.com
+380715314579	1982	Iva	Brakus	Asa.Bartell13@hotmail.com
+380716098940	1919	Margarete	Howell	Arnaldo0@gmail.com
+380716125252	1838	Mckenzie	Schmidt	Dedrick_Toy@yahoo.com
+380716574432	1736	Katherine	Watsica	Alphonso_Feest20@yahoo.com
+380718228777	1680	Annette	Nienow	Oceane_Jacobs31@yahoo.com
+380719393252	1732	Simeon	Grady	Carol14@hotmail.com
+380720531155	1894	Jeromy	O'Hara	Elissa_Schmitt@hotmail.com
+380721066625	1734	Nikki	Gutmann	Weston_Hahn@gmail.com
+380722149706	1884	Rahul	Terry	Christ_Emmerich34@gmail.com
+380723762990	1978	Walter	Gleason	Thea.Parker60@gmail.com
+380724440694	1821	Carmen	Bauch	Avery94@hotmail.com
+380726996084	1664	Thora	Anderson	Howell_Luettgen@hotmail.com
+380727378267	1795	Amelie	Beatty	Caterina.Bernier39@yahoo.com
+380727611642	1597	Tierra	Kozey	Melisa21@yahoo.com
+380727636408	1526	Marcella	Runte	Calista_Osinski27@yahoo.com
+380727990734	1850	Ollie	Goyette	Sarah56@gmail.com
+380728079412	1545	Gene	Abernathy	Rozella_Predovic89@yahoo.com
+380728604041	1889	Favian	Muller	Frances93@gmail.com
+380731278055	1811	Alessia	Kilback	Bart_OKeefe62@gmail.com
+380731962568	1974	Jaquelin	Hettinger	Cooper_Lakin71@hotmail.com
+380732304176	1734	Brittany	Russel	Amina.Wuckert@hotmail.com
+380733976951	1821	Delphine	Streich	Christophe.Bogisich53@yahoo.com
+380734501443	1928	Allen	Bogan	Hardy78@yahoo.com
+380735628666	1589	Nelda	Legros	Dashawn_Marvin97@gmail.com
+380736117138	1527	Dorothea	Wuckert	Bulah1@yahoo.com
+380736506547	1851	Merritt	Ruecker	Hosea84@gmail.com
+380737537839	1898	Chanel	Harber	Cassandre27@hotmail.com
+380737706943	1627	Herman	Walsh	Lemuel97@hotmail.com
+380738063537	1721	Gabriella	Lindgren	Damion.Parker@yahoo.com
+380738541167	1794	Maida	Hintz	Augustine_Cormier66@hotmail.com
+380739819586	1809	Isidro	Wiza	Julia.Robel@yahoo.com
+380739892088	1652	Jaycee	Stiedemann	Quentin_Green@hotmail.com
+380740084975	1767	Yasmeen	Schmeler	Rebeka.Kovacek@hotmail.com
+380742139134	1787	Dominic	Collier	Dangelo42@hotmail.com
+380742980373	1552	Malika	Haag	Troy.Gleason17@yahoo.com
+380743180055	1618	Lolita	Jones	Briana_Monahan26@gmail.com
+380746810618	1867	Coty	Schmitt	Tanner.Hyatt@gmail.com
+380746840638	1752	Johnson	Carroll	Toy.Miller@gmail.com
+380746920564	1930	Elsa	Friesen	Louie_Jast@yahoo.com
+380747367067	1893	Keely	Collier	Karen_Parisian@gmail.com
+380747833451	1732	Garnett	Doyle	Quinton_Jast93@yahoo.com
+380748235651	1573	Jakob	Brakus	Monroe_MacGyver@hotmail.com
+380748409658	1563	Celine	Stamm	Ashly_Gusikowski78@hotmail.com
+380748432542	1567	Brennon	Berge	Laurel_Murray@yahoo.com
+380748601224	1732	Malachi	Ondricka	Luella.Gleason@hotmail.com
+380748829582	1732	Austen	Labadie	Mason4@gmail.com
+380749389078	1745	Valentin	Pouros	Marguerite18@yahoo.com
+380749717101	1554	Kailyn	Kiehn	Liana98@yahoo.com
+380750325037	1521	Madalyn	Funk	Benedict_Hills@hotmail.com
+380750573490	1518	Dolores	Keebler	Sadie0@gmail.com
+380751217885	1555	Gabriel	Connelly	Alejandrin.Deckow@hotmail.com
+380751758633	1659	Santa	Skiles	Jan.Bayer@hotmail.com
+380752112117	1727	Ismael	Welch	Manley_Hansen@hotmail.com
+380753497981	1654	Colin	Cummings	Rafael_Blanda@gmail.com
+380754409243	1704	Deontae	Cronin	Laila49@hotmail.com
+380754829835	1776	Henriette	Dooley	Brody.Hilpert@hotmail.com
+380754830844	1905	Jessika	Christiansen	Godfrey3@hotmail.com
+380755282619	1656	Keaton	Hegmann	Sylvia85@yahoo.com
+380755839532	1694	Kiara	Kris	Parker_Beahan38@yahoo.com
+380756091998	1585	Raven	Effertz	Jayde_Reynolds98@hotmail.com
+380756196822	1843	Nola	Boyle	Wellington.Beahan17@yahoo.com
+380756788622	1710	Ruthie	Heller	Lew19@hotmail.com
+380757026952	1557	Marilou	Osinski	Patience59@gmail.com
+380758044572	1867	Tate	Harris	Mia.Connelly11@yahoo.com
+380758673536	1953	Lera	Sauer	Josephine.Cartwright79@gmail.com
+380760316297	1696	Rogelio	Fisher	Amara.Willms43@yahoo.com
+380760846680	1897	Claire	Rolfson	Irwin.Jones@hotmail.com
+380761071834	1905	Josefina	Rogahn	Walton_Turcotte@gmail.com
+380761240085	1915	Michale	Thompson	Tianna_Schuppe@gmail.com
+380761748254	1958	Esmeralda	Schneider	Arlene.Mitchell@hotmail.com
+380762134287	1863	Joelle	Erdman	Khalil32@hotmail.com
+380764535355	1729	Pearl	Rowe	Leif75@yahoo.com
+380765820240	1988	Cooper	Lind	Britney.Dicki43@gmail.com
+380766212984	1752	Beth	Boehm	Casimir_Yundt@gmail.com
+380769188687	1801	Oran	Labadie	Lesley73@yahoo.com
+380769350290	1964	Friedrich	Gutkowski	Ezekiel_Stanton@yahoo.com
+380769363261	1586	Otis	Ryan	Kelsi.Crona@yahoo.com
+380770094198	1656	Tamara	Halvorson	Earnestine35@gmail.com
+380770696237	1854	Reva	Hegmann	Sigmund5@hotmail.com
+380771197510	1857	Cierra	Medhurst	Sylvan.OHara@yahoo.com
+380771603705	1643	Stephany	Dickinson	Erica2@yahoo.com
+380772231114	1918	Ashleigh	Mitchell	Norwood.Hartmann76@hotmail.com
+380772390884	1512	Damion	Roob	Berry_Gusikowski@gmail.com
+380772491933	1782	Vicky	Grady	Patience45@hotmail.com
+380772620825	2001	Jimmy	Feil	Gilberto.Buckridge9@yahoo.com
+380772864936	1854	Guy	Harvey	Hazle21@gmail.com
+380774020045	1865	Cierra	Romaguera	Kendall.Hickle22@gmail.com
+380774669502	1896	Arielle	Thompson	Marcelino_Bauch28@yahoo.com
+380775173763	1542	Hillard	Turcotte	Dedric24@yahoo.com
+380775388467	1527	Mya	Kling	Tia77@yahoo.com
+380775891225	1975	Jon	Mayert	Veronica75@gmail.com
+380776206084	1969	Jace	Blanda	Ofelia55@yahoo.com
+380776568567	1983	Aimee	Russel	Noemi_Hackett@gmail.com
+380778033448	1698	Norwood	Zboncak	Sofia49@gmail.com
+380778215942	1991	Jerrell	Boyer	Murphy_Hamill@yahoo.com
+380778855407	1803	Mariela	Hammes	Royce.Fadel@gmail.com
+380779982740	1925	Thalia	Berge	Isadore55@hotmail.com
+380781089361	1567	Ernestina	Durgan	Jakob_Armstrong49@yahoo.com
+380781134648	1563	Davion	McDermott	Eldridge43@yahoo.com
+380782288673	1539	Layla	Kling	Adan.Considine4@yahoo.com
+380782755499	1996	Sammie	Gleason	Marco_Swift@gmail.com
+380782856994	1571	Annette	Tromp	Shayne_OReilly33@yahoo.com
+380783261892	1613	Lacey	Parisian	Cornelius.Goyette@gmail.com
+380784289249	1922	Lee	Carroll	Lorena.Senger74@yahoo.com
+380785706964	1876	Heidi	Howell	Elvera14@hotmail.com
+380785964449	1534	Hank	Haley	Savanna_Tillman@hotmail.com
+380786069308	1876	Maye	Schuster	Arnaldo.Kunde@hotmail.com
+380787447122	1521	Krystel	Ernser	Rosa_Kassulke43@yahoo.com
+380787506850	1803	Brant	Brown	Ryann50@hotmail.com
+380787564707	1631	Dejuan	Cummerata	Effie.Mohr14@gmail.com
+380788058521	1838	Fabiola	Wiegand	Sasha.Balistreri96@hotmail.com
+380789074387	1541	Llewellyn	Tillman	Whitney38@hotmail.com
+380789307856	1903	Madelynn	Tremblay	Leatha.Funk@gmail.com
+380789522048	1729	Tia	Rau	Therese.Turcotte1@gmail.com
+380789992375	1568	Evangeline	Schuster	Carmel79@hotmail.com
+380790565295	1971	Jovan	Rolfson	Herminio_Quigley94@yahoo.com
+380791358592	1752	Lurline	Watsica	Russel_Smith64@yahoo.com
+380791735147	1962	Carley	Krajcik	Leatha41@gmail.com
+380791938959	1693	Saul	Ziemann	Cortez_Zboncak47@gmail.com
+380793572222	1592	Reba	Tromp	Monique.Sawayn@hotmail.com
+380794222962	1802	Jaylin	Bashirian	Jalon55@yahoo.com
+380794312439	1958	Cassandra	Tillman	Donald_Ryan95@yahoo.com
+380794776985	1634	Chandler	Klein	Willard_Bayer@yahoo.com
+380795366979	1779	Ray	Yundt	Reta.Quigley72@hotmail.com
+380795615091	1875	Johnathon	Abshire	Joy.Barrows59@hotmail.com
+380796063577	1534	Emmanuelle	Schowalter	Emelia_OConnell@yahoo.com
+380796968711	1691	Melissa	Kub	Dortha_Bradtke@gmail.com
+380797060959	1622	Oceane	Lesch	Mathias.Johnson40@yahoo.com
+380797160557	1752	Maynard	Marquardt	Karlie78@gmail.com
+380797316115	1823	Kayleigh	Satterfield	Wyman38@yahoo.com
+380798607871	1761	Afton	Lind	Naomie46@yahoo.com
+380800173906	1686	Kolby	Hamill	Jarret.Gutmann74@gmail.com
+380800324347	1834	Stephon	Grimes	Edison84@yahoo.com
+380800876614	1611	Earl	Harvey	Julio37@yahoo.com
+380802563562	1599	Orville	Schamberger	Prudence_Feeney42@gmail.com
+380802832475	1949	Icie	Nader	Dwight_Adams98@yahoo.com
+380803083401	1517	Dereck	Doyle	Anastasia81@gmail.com
+380803290834	1735	Palma	Nienow	Georgianna_Schaefer@gmail.com
+380805328635	1843	Allene	Koch	Verna_Price83@hotmail.com
+380805330692	1624	Tracey	Runte	Augustus.Metz69@yahoo.com
+380806398244	1808	Aida	Treutel	Elbert_Schmidt13@yahoo.com
+380806415808	1833	Kris	Oberbrunner	Kamryn_Bauch33@yahoo.com
+380807355841	1732	Mackenzie	Gislason	Lucious_Weissnat@yahoo.com
+380808401733	1825	Michael	Luettgen	Kraig.Hagenes55@hotmail.com
+380809449010	1732	Conor	Hyatt	Fredrick_Mohr26@yahoo.com
+380809556569	1641	Candida	Yost	Daniela7@gmail.com
+380809860555	1667	Gordon	Gerhold	Robin.Casper@gmail.com
+380810146870	1844	Jana	Johnson	Eda_Kunde@yahoo.com
+380810597397	1753	Tara	Kub	Marisol88@gmail.com
+380811026145	1521	Allison	Torp	Ruthe.Zieme83@yahoo.com
+380811795848	1760	Kiley	Kerluke	Reina58@hotmail.com
+380812566394	1508	Oma	Wintheiser	Juwan67@yahoo.com
+380812912286	1527	Marlen	Conn	Coty.OConner49@yahoo.com
+380813373532	1580	Ashly	Buckridge	Alex37@hotmail.com
+380814160104	1701	Tyrese	Beer	Hazle17@hotmail.com
+380814636468	1698	Watson	Osinski	Andrew_Considine82@yahoo.com
+380814923310	1803	Mallory	Hirthe	Ashley_Reichel72@yahoo.com
+380815028479	1632	Vance	Hettinger	Oceane_Jast@yahoo.com
+380815033913	1572	Kian	Kozey	Priscilla.Abernathy@hotmail.com
+380816818464	1554	Paige	Connelly	Dameon.Zieme@hotmail.com
+380817280453	1852	Laurianne	Oberbrunner	Lacy_Towne26@hotmail.com
+380817508231	1558	Liana	Hamill	Kian33@yahoo.com
+380818877855	1575	Ronaldo	Corwin	Devon.Hoppe77@yahoo.com
+380819998224	1712	Agustina	Doyle	Amaya.Simonis@yahoo.com
+380821132871	1674	Odie	Bayer	Richmond.Aufderhar43@yahoo.com
+380821359775	1929	Walton	Hilll	Jaida.Schmidt@gmail.com
+380821635966	1958	Octavia	Bednar	Heaven_Murazik80@gmail.com
+380821658934	1788	Miguel	Schmidt	Rory40@gmail.com
+380821975553	1733	Wilton	Fay	King.Nicolas49@hotmail.com
+380822306269	1829	Karelle	Quigley	Wilfred.Lang50@hotmail.com
+380822617976	1927	Arielle	Spinka	Ford57@yahoo.com
+380824961903	1731	Viola	Denesik	Hermina55@gmail.com
+380825019559	1716	Laron	Reynolds	Lizeth35@gmail.com
+380826755593	1672	Lorenzo	Lind	Janae.Gulgowski@yahoo.com
+380828080172	1710	Hilario	Runolfsson	Jessie12@yahoo.com
+380828282835	1893	Brook	Bayer	Princess.Dibbert@yahoo.com
+380829240717	1614	Geraldine	Nienow	Shea.Homenick@gmail.com
+380829244154	1934	Merl	Langosh	Kaya.Lowe@yahoo.com
+380830791020	1547	Rebeca	Collins	Nasir12@gmail.com
+380831205595	1845	Joseph	Schmeler	Jaclyn.Luettgen2@hotmail.com
+380831580992	1708	Lauren	Leuschke	Rodolfo.Zieme@hotmail.com
+380831846112	1619	Brycen	Rau	Brianne_Armstrong21@gmail.com
+380832932573	1776	Myra	Harber	Brandi.Moore64@hotmail.com
+380833198692	1940	Elsa	Pagac	Cyril_Lehner@yahoo.com
+380835748582	1785	Granville	Johnston	Trisha.OConner69@hotmail.com
+380836237391	1512	Aurelio	Boehm	Hoyt52@gmail.com
+380836331025	1511	Baby	Ferry	Maxwell.Schulist@yahoo.com
+380836718833	1766	Drake	Rau	Griffin67@hotmail.com
+380836724402	1798	Carmel	Rohan	Shawn.Crooks@yahoo.com
+380837379359	1754	Montana	Erdman	Ariel99@gmail.com
+380837913620	1813	Alexzander	Heaney	Johanna.Rempel@gmail.com
+380838405119	1923	Rasheed	Strosin	Arturo.Franecki57@hotmail.com
+380839057222	1957	Harold	Streich	Ethyl.Corwin@yahoo.com
+380841027980	1990	Holden	Spinka	Maverick34@hotmail.com
+380842889052	2001	Lizzie	Schoen	Trycia49@hotmail.com
+380843624836	1828	Elisha	Carroll	Judy75@gmail.com
+380844032677	1761	Ezequiel	Zemlak	Mabel82@hotmail.com
+380844452985	1846	Vivien	Hills	Vivianne_Breitenberg83@hotmail.com
+380844546721	1960	Paxton	Dach	Presley_Powlowski49@gmail.com
+380844581724	1711	Tamia	Auer	Wava_Greenholt@hotmail.com
+380845297846	1932	Brandi	Bartell	Lelah_Tillman78@yahoo.com
+380845836473	1952	Sanford	Beier	Elnora19@gmail.com
+380845934685	1904	Jerod	Mitchell	Dudley_Stamm8@gmail.com
+380845945593	1505	Colten	Volkman	Marlene_Parker3@yahoo.com
+380846196149	1962	Flavie	Upton	Laney.Mann29@yahoo.com
+380846697634	1780	Madaline	Kuvalis	Katlyn93@gmail.com
+380847468056	1959	Velda	Schaefer	Magdalen67@yahoo.com
+380847906776	1521	Solon	Deckow	Halle_Mayert@yahoo.com
+380848265868	1894	Avis	Trantow	Janie54@yahoo.com
+380848525913	1651	Noble	Wehner	Jose_Nicolas@yahoo.com
+380848597403	1620	Alberto	Balistreri	Haley_Kling11@yahoo.com
+380848802498	1761	Darian	Dare	Malvina21@yahoo.com
+380848835681	1768	Estell	Auer	Helga98@yahoo.com
+380849254990	1650	Ashleigh	Harris	Jovan42@yahoo.com
+380849329178	1516	Stanford	Schuppe	Betsy.Dickens@hotmail.com
+380850470967	1908	Carson	Herman	Greg.Douglas16@hotmail.com
+380851459037	1546	Tia	Ryan	Roger52@gmail.com
+380851833088	1584	Emile	Roberts	Ladarius.Zulauf13@hotmail.com
+380851959731	1611	Johathan	Mosciski	Hailee.Grant@gmail.com
+380852390701	1851	Muhammad	Fay	Jamison.Shanahan75@hotmail.com
+380852873609	1745	Marvin	Champlin	Missouri_Ledner38@hotmail.com
+380855586146	1626	Lyric	Emard	Matt.Reinger7@gmail.com
+380855723469	1797	Tamia	Doyle	Jefferey82@gmail.com
+380855840424	1751	Quentin	Frami	Lavina.Rippin@gmail.com
+380857797941	1669	Annalise	Bauch	Amos_Schamberger43@hotmail.com
+380858494040	1862	Oma	Schowalter	Onie.Balistreri@hotmail.com
+380858702370	1676	Billie	Morar	Eloisa.Romaguera71@yahoo.com
+380859035414	1678	Una	Beier	Delilah.Hamill@yahoo.com
+380859504861	1980	Mckayla	Cummerata	Magnolia_Frami62@yahoo.com
+380859936324	1778	Wyman	McGlynn	Rafaela61@gmail.com
+380860052833	1748	Roel	Hartmann	Annabel.Howe@gmail.com
+380860145821	1541	Cyril	Prosacco	Kiarra.Gleason56@yahoo.com
+380860205214	1628	Elenor	Hansen	Kim.Walter@gmail.com
+380860435785	1525	Stephany	Runolfsdottir	Dangelo.Hayes@hotmail.com
+380860855878	1969	Maria	Funk	Cora_Orn@yahoo.com
+380860975668	1708	Ramiro	Ebert	Lucinda78@yahoo.com
+380861811310	1902	Gianni	Crooks	Llewellyn_Langworth@yahoo.com
+380862260262	1611	Eulalia	Kirlin	Mustafa.Bradtke@hotmail.com
+380862311085	1721	Herminio	Carter	Trent.Gutkowski@gmail.com
+380862434944	1566	Jaden	Ward	Damaris29@yahoo.com
+380862490596	1730	Jaqueline	Rempel	Angelina80@yahoo.com
+380863155618	1566	Colten	Thompson	Rudolph.Watsica@hotmail.com
+380863200151	1980	Tamara	O'Conner	Magdalen.Littel39@yahoo.com
+380864973779	1770	Christiana	Greenfelder	Ivah.Zulauf24@gmail.com
+380865015136	1650	Moriah	Rice	Hermina.Jerde@yahoo.com
+380865428478	1834	Amparo	Murray	Beau_Rau37@yahoo.com
+380865568120	1643	Alize	Runte	Fern_Christiansen@hotmail.com
+380865707466	1706	Madelynn	Trantow	Kassandra.Homenick@hotmail.com
+380868062874	1536	Queen	Abbott	Winona_Muller@gmail.com
+380868521950	1775	Alene	Shanahan	Ayla_Torp7@hotmail.com
+380868953078	1768	Adrianna	Satterfield	Patience31@hotmail.com
+380869534011	1534	Berry	Frami	Zoie.Wolf10@yahoo.com
+380869755151	1887	Abner	Carter	Thomas85@yahoo.com
+380870157763	1824	Phyllis	Reynolds	Estella.Collins82@gmail.com
+380870603474	1963	Genevieve	Nicolas	Jarrell.Klocko@hotmail.com
+380870745384	1999	Deborah	White	Earnest9@yahoo.com
+380871570209	1892	Novella	Rolfson	Zachariah58@hotmail.com
+380872018119	1536	Gretchen	Ondricka	Rosie0@gmail.com
+380873237755	1801	Johnny	Buckridge	Blake_Carroll68@hotmail.com
+380874529285	1566	Luigi	Rutherford	Stanton.Hegmann6@hotmail.com
+380875733986	1607	Garth	Doyle	Jamir.Upton35@gmail.com
+380875852083	1556	Hayley	Nikolaus	Hal93@yahoo.com
+380876136695	1517	Hulda	King	Brody_Deckow26@yahoo.com
+380876434451	1720	Cruz	Heidenreich	General.Raynor79@yahoo.com
+380877754775	1648	Bertha	Kirlin	Estrella8@yahoo.com
+380878297787	1655	Stephen	Sanford	Gabe.Krajcik31@yahoo.com
+380878394833	1788	Krista	Schaden	Aurore_Feeney@yahoo.com
+380878432268	1749	Paxton	Ondricka	Rowan_Reynolds13@gmail.com
+380879036811	1956	Guillermo	Balistreri	Gunner72@yahoo.com
+380879457494	1801	Alvah	Pagac	Fred31@gmail.com
+380879844281	1747	Kennedy	Weimann	Rusty92@hotmail.com
+380880751037	1655	Joshua	Bradtke	Pearline_King@yahoo.com
+380881149099	1678	Elton	Gusikowski	Joany54@yahoo.com
+380881404191	1637	Elmo	Goodwin	Maryam3@gmail.com
+380882099632	1736	Loren	Cruickshank	Jaren_Franecki@gmail.com
+380883150669	1692	Cristina	Ritchie	Samantha.Blick5@gmail.com
+380883388292	1603	Broderick	Bins	Emilia.Stark22@hotmail.com
+380883519039	1977	Emerald	Ferry	Ayana_Larkin@yahoo.com
+380883779713	1620	Noemie	Jacobson	Katharina_McGlynn@hotmail.com
+380884136165	1808	Gabrielle	Murray	Brody.Hand78@yahoo.com
+380886324546	1714	Karianne	Gutkowski	Michaela_Schmidt@hotmail.com
+380887185308	1629	Ashlee	Grant	Arne_Klein@gmail.com
+380887449438	1797	Josie	Strosin	Orie.Volkman43@hotmail.com
+380887492957	1925	Rossie	Larkin	Chesley_Jakubowski@hotmail.com
+380887716619	1732	Matt	Feeney	Kaden.Ledner@hotmail.com
+380889142423	1649	Eric	Pagac	Gabrielle3@yahoo.com
+380889248621	1740	Palma	Ward	Maurice_Kub@gmail.com
+380892785334	1654	Devon	Gusikowski	Kassandra_Gibson@hotmail.com
+380893284386	1829	Giovanni	Rau	Aniya.Renner20@gmail.com
+380893712748	1991	Columbus	Jenkins	Alec.Purdy@hotmail.com
+380895113746	1763	Ramiro	Hintz	Ezekiel.Jacobson@yahoo.com
+380895767177	1673	Ricardo	Pacocha	Jalen_Adams4@yahoo.com
+380897908118	1805	Gail	Shanahan	Lloyd56@yahoo.com
+380898354809	1905	Karine	Erdman	Shaylee.Hauck@gmail.com
+380900341352	1690	Shea	Raynor	Narciso.Barrows61@hotmail.com
+380902220891	1828	Hubert	Berge	Gaylord.Armstrong74@gmail.com
+380902904398	1698	Nicholas	Simonis	Otilia18@yahoo.com
+380902949568	1706	Clementine	Kilback	Fermin28@hotmail.com
+380903881006	1612	Mark	Ritchie	Urban_Hayes@gmail.com
+380904691225	1770	Lauriane	Barton	Ethyl99@yahoo.com
+380905755156	1672	Johann	Hansen	Hollis_Thompson46@gmail.com
+380905856732	1576	Earline	Cormier	Aida.Barton@gmail.com
+380907800993	1725	Madonna	Wintheiser	Lulu.Stiedemann@hotmail.com
+380909540554	1519	Giovani	Carroll	Zaria_Gaylord@yahoo.com
+380910889105	1860	Herta	Aufderhar	Shane.Vandervort@yahoo.com
+380911109543	1948	Rhianna	Deckow	Jevon_Green46@gmail.com
+380911129323	1688	Gerald	Ebert	America6@yahoo.com
+380911208118	1849	Ewell	Robel	Quentin87@hotmail.com
+380911245449	1988	Martine	Bahringer	Maye8@hotmail.com
+380911779840	1661	Richard	Gorczany	Brandy_Rempel@gmail.com
+380912294177	1517	Corene	Bauch	Leonard.Goldner48@gmail.com
+380912330581	1612	Keshawn	Gleichner	Natalia.Lind@gmail.com
+380912725703	1668	Gaetano	Hagenes	Forest.Kuhic44@gmail.com
+380913243911	1960	Orval	Lind	Carlie.Prohaska84@hotmail.com
+380913518668	1934	Grace	Stroman	Roslyn7@hotmail.com
+380916424759	1846	Faye	Emard	Madonna.Auer@yahoo.com
+380917025525	1695	Louvenia	Rice	Cicero43@gmail.com
+380917192323	1591	Bonnie	Crooks	Leda.Buckridge@gmail.com
+380917485664	1709	Isobel	Stoltenberg	Zola_Kuvalis@gmail.com
+380918954464	1846	Vinnie	Murazik	Dandre.Smith@hotmail.com
+380920456009	1847	Antwan	Dooley	Eveline_Funk87@hotmail.com
+380920721350	1822	Nigel	Schroeder	Aryanna88@hotmail.com
+380921093661	1790	Jakob	Pagac	Isabella.Wisozk@gmail.com
+380921202362	1684	Zetta	Osinski	Rogelio_Kilback73@gmail.com
+380922829512	1825	Annalise	Bins	Lacy92@gmail.com
+380924196412	1752	Avis	Rau	Sibyl7@gmail.com
+380924289727	1773	Nathaniel	Shields	Bernardo50@gmail.com
+380925559352	1730	Conner	Dooley	Dell19@hotmail.com
+380925859117	1960	Keyon	Willms	Alize.Reichel@gmail.com
+380926465925	1950	Aubree	Brakus	Stone.Lesch65@yahoo.com
+380927223359	1574	Shannon	Toy	Gloria.Nienow@hotmail.com
+380928116288	1854	Celestine	Daugherty	Freda.Corkery@gmail.com
+380928512482	1597	Derek	Ryan	Coty_Block12@gmail.com
+380928671484	1826	Lew	Feest	Lila_Champlin@hotmail.com
+380928922217	1832	Imelda	Kuhlman	Sam_Terry53@gmail.com
+380929014221	1862	Bonnie	Cremin	Ariane_Carroll16@yahoo.com
+380929248960	1999	Deja	Rolfson	Barry80@hotmail.com
+380930387393	1760	Immanuel	Maggio	Ruben29@hotmail.com
+380931890195	1935	Kris	Runte	Jacinthe.Bahringer@yahoo.com
+380932017790	1590	Vida	Larson	Jacky63@yahoo.com
+380932392953	1572	Gaston	Hackett	Magnolia80@gmail.com
+380932486658	1846	Fredrick	Ernser	Kali_Dooley62@hotmail.com
+380933664477	1646	Trace	Weber	Charlotte5@yahoo.com
+380933928381	1668	Everardo	Cruickshank	Ima_Greenholt18@gmail.com
+380934218939	1885	Sydnee	Hayes	Mozell_Walker11@hotmail.com
+380936354086	1571	Catalina	Kshlerin	Fredrick81@yahoo.com
+380937221770	1541	Ludwig	Zemlak	Marguerite.Corkery@hotmail.com
+380938286080	1692	Ariel	Harris	Maverick29@yahoo.com
+380938892706	1797	Alvena	Wilderman	Misael.Medhurst91@yahoo.com
+380939437483	1918	Kip	Schneider	Kathleen.Dare@yahoo.com
+380940664403	1623	Angel	Leffler	Erik.Johnston93@gmail.com
+380941052916	1984	Trey	Morissette	Frieda54@gmail.com
+380941860349	1983	Karlie	Boehm	Rex57@yahoo.com
+380942392292	1639	Olga	Trantow	Trever.Hills20@gmail.com
+380942684170	1683	Mariam	Graham	Cary80@gmail.com
+380943266053	1560	Maximillia	O'Hara	Reagan_Ankunding@gmail.com
+380944659943	1888	Lue	Feil	Noelia91@yahoo.com
+380945467951	1827	Bret	Kutch	Myrl83@hotmail.com
+380945516977	1828	Katheryn	Hartmann	Macy_Ortiz85@yahoo.com
+380946778267	1953	Emmalee	Collins	Clemens.Cummings34@gmail.com
+380948439588	1868	Maddison	Becker	Johnathon_McClure7@hotmail.com
+380948921479	1932	Emma	Zieme	Alexis_Davis@gmail.com
+380949318014	1578	Dudley	Murazik	Anthony_Orn96@yahoo.com
+380949484743	1802	Aurelio	Grimes	Noemie_Torp@gmail.com
+380949502137	1671	Jackie	Raynor	Seamus_Pagac@hotmail.com
+380949579020	1520	Declan	Upton	Jabari56@gmail.com
+380949652801	1622	Jimmie	Ziemann	Mabel_Grimes98@hotmail.com
+380949671873	1999	Genoveva	Legros	Margot.Pfeffer@hotmail.com
+380950260973	1658	Kenyatta	Von	Hudson45@hotmail.com
+380953959757	1912	Nash	Balistreri	Guy5@yahoo.com
+380954570861	1589	Cloyd	O'Kon	Diana_Grimes@hotmail.com
+380954602151	1967	Taryn	Lakin	Agustin.Koepp@yahoo.com
+380957492399	1752	Brandi	Fisher	Mekhi_Homenick@gmail.com
+380958890142	1594	Quincy	Weissnat	Cordie_Kuvalis21@yahoo.com
+380959542527	1898	Rogelio	Nader	Madelyn_Christiansen73@yahoo.com
+380960313160	1836	Kaci	Bogan	Lizeth_Boyer90@hotmail.com
+380960470548	1973	Ella	Leuschke	Lois3@yahoo.com
+380960803078	1722	Dedric	Gusikowski	Lurline91@gmail.com
+380961656322	1800	Fermin	Sauer	Yessenia72@hotmail.com
+380961907580	1796	Margarette	Daugherty	Tony26@hotmail.com
+380961952482	1568	Alessia	Terry	Kristin_Casper@hotmail.com
+380963603293	1792	Ralph	Sipes	Bonnie51@gmail.com
+380963610080	1759	Lina	Lehner	Flossie_Heathcote@hotmail.com
+380964079778	1732	Ewell	Hodkiewicz	Onie77@gmail.com
+380964110933	1972	Francisca	Pollich	Isai42@hotmail.com
+380965982395	1728	Mable	Schmitt	Arnoldo_Emmerich@hotmail.com
+380966974350	1617	Delia	Homenick	Elinore_Mertz89@yahoo.com
+380967446828	1888	Edwina	Goldner	Margarette_Rosenbaum10@yahoo.com
+380967701802	1800	Florida	Doyle	Halle48@hotmail.com
+380967793515	1747	Kaylah	Kuphal	Maximus.Blanda80@yahoo.com
+380969969919	1745	Van	Klein	Ozella32@hotmail.com
+380970592700	1587	Josh	Braun	Mariela.Paucek75@yahoo.com
+380970596100	1618	Madie	Monahan	Gerhard.Funk@yahoo.com
+380971091744	1750	Kamron	Kuphal	Marjory_Marquardt@hotmail.com
+380971946007	1959	Alexander	Terry	Cassidy_Grant@gmail.com
+380972702290	1800	Roosevelt	Goldner	Shakira.Schimmel@yahoo.com
+380972833863	1874	Ricardo	Wilkinson	Isabella46@hotmail.com
+380972914002	1633	Grant	Kunze	Torey26@gmail.com
+380973076459	1677	Tess	Daugherty	Hazle_Krajcik@gmail.com
+380973183824	1700	Lennie	Konopelski	Linda.Leuschke10@hotmail.com
+380973714702	1706	Treva	Grady	Jeff40@yahoo.com
+380975101086	1841	Lina	Marvin	Elvera34@gmail.com
+380978135647	1892	Martine	Carroll	Everett.McKenzie23@gmail.com
+380979321997	1575	Patience	Watsica	Dewayne99@gmail.com
+380979767218	1998	Zachariah	Waters	Gillian.Dach@yahoo.com
+380980025486	1722	Phoebe	Stiedemann	Bradford_Cartwright@gmail.com
+380981137697	1775	Sylvan	Heaney	Preston.Hagenes15@yahoo.com
+380982953042	1776	Maxie	Cummerata	Lafayette_Wolff@yahoo.com
+380983594425	1823	Gwen	Rath	Kylee.Tromp74@gmail.com
+380983681302	1736	Kamryn	Ruecker	Alvena_Gibson@yahoo.com
+380984685418	1943	Ashlee	Wuckert	Ericka70@hotmail.com
+380984972845	1865	Dulce	Durgan	Jakayla92@hotmail.com
+380985498301	1892	Linnea	Medhurst	June.Schowalter@hotmail.com
+380986026505	2001	Ephraim	Mayert	Moses.Mayer68@gmail.com
+380986538996	1563	Vada	Reichert	Allen45@hotmail.com
+380988138032	1846	Vicente	Schuster	Natasha_Stiedemann18@yahoo.com
+380988518819	1954	Robbie	Tremblay	Serenity81@hotmail.com
+380988675784	1689	Trudie	Price	Miller_Hand67@hotmail.com
+380989493604	1518	Maxine	Lubowitz	Zackery51@hotmail.com
+380989553593	1538	Sheila	Keeling	Agustin80@yahoo.com
+380989625889	1792	Leonor	Hand	Wilber_Streich11@hotmail.com
+380989688170	1531	Alexis	Glover	Daija_Little28@yahoo.com
+380989879136	1922	Brielle	Armstrong	Marisol.Krajcik@yahoo.com
+380990879925	1886	Merritt	Ward	Jarred.Purdy@yahoo.com
+380991204563	1520	Hallie	Beier	Bernie9@gmail.com
+380991983561	1948	Heaven	Jerde	Brad37@hotmail.com
+380993054133	1808	Hertha	Huels	Alf32@hotmail.com
+380993992205	1908	Santos	Witting	Asha70@yahoo.com
+380994290563	1710	Adrian	Ankunding	Clare_Reichel@hotmail.com
+380994499738	1782	Laurianne	Collier	Guadalupe_Tremblay39@gmail.com
+380994605375	1846	Larue	Lindgren	Hayden20@yahoo.com
+380995175965	1827	Jade	Dickens	Alexandra_Pfeffer@hotmail.com
+380995194090	1547	Ashtyn	Bayer	Santa.Hagenes@hotmail.com
+380995263924	1768	Clifton	Roberts	Vernie_Kiehn@gmail.com
+380996723283	1579	Francesca	Hintz	Modesto.Kemmer@hotmail.com
+380996838491	1795	Valentine	Blanda	Gage_Muller82@hotmail.com
+380998539812	1987	Dejon	Ortiz	Shayne_Yundt@yahoo.com
+380998680148	1612	Velma	Bradtke	Jovanny.Hintz@gmail.com
+380998756817	1733	Lacy	McDermott	Denis.Satterfield53@yahoo.com
+380998865929	1871	Durward	Gaylord	Tony.Keeling@yahoo.com
+380999719096	1691	Trace	Hyatt	Einar.Watsica32@gmail.com
+380007707486	1926	Maximilian	McLaughlin	\N
+89725678197	1510	John	Smith	\N
+380409094908	1510	Johnny	Marvin	Penelope13@hotmail.com
+36748926489	1510	HJGHGJG12	GGKJGKJ	\N
\.


--
-- TOC entry 4950 (class 0 OID 16581)
-- Dependencies: 225
-- Data for Name: storage_product; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.storage_product (storage_id, product_name, count) FROM stdin;
1515	Awesome Cotton Gloves	5.44
1549	Awesome Cotton Gloves	97.54
1554	Awesome Cotton Gloves	58.31
1580	Awesome Cotton Gloves	68.47
1706	Awesome Cotton Gloves	71.72
1737	Awesome Cotton Gloves	54.59
1930	Awesome Cotton Gloves	19.27
1661	Awesome Cotton Sausages	84.72
1752	Awesome Cotton Sausages	28.30
1761	Awesome Cotton Sausages	92.74
1811	Awesome Cotton Sausages	74.13
1837	Awesome Cotton Sausages	92.05
1971	Awesome Cotton Sausages	86.69
1983	Awesome Cotton Sausages	27.33
1563	Awesome Fresh Chicken	24.15
1738	Awesome Fresh Chicken	74.24
1794	Awesome Fresh Chicken	71.09
1526	Awesome Fresh Chips	8.66
1643	Awesome Fresh Chips	7.64
1661	Awesome Fresh Chips	90.71
1673	Awesome Fresh Chips	24.12
1678	Awesome Fresh Chips	84.26
1752	Awesome Fresh Chips	83.77
1883	Awesome Fresh Chips	96.75
1949	Awesome Fresh Chips	88.09
1964	Awesome Fresh Chips	83.22
2001	Awesome Fresh Chips	85.38
1588	Awesome Metal Hat	85.53
1674	Awesome Metal Hat	16.80
1782	Awesome Metal Hat	54.11
1927	Awesome Metal Hat	10.19
1559	Awesome Metal Shoes	84.87
1569	Awesome Metal Shoes	25.70
1738	Awesome Metal Shoes	12.19
1752	Awesome Metal Shoes	83.00
1786	Awesome Metal Shoes	71.98
1880	Awesome Metal Shoes	16.13
1625	Awesome Plastic Tuna	70.14
1842	Awesome Plastic Tuna	99.93
1881	Awesome Plastic Tuna	85.52
1905	Awesome Plastic Tuna	74.81
1525	Awesome Rubber Soap	30.57
1534	Awesome Rubber Soap	96.00
1653	Awesome Rubber Soap	67.37
1779	Awesome Rubber Soap	3.18
1879	Awesome Rubber Soap	95.47
1563	Ergonomic Fresh Mouse	52.45
1774	Ergonomic Fresh Mouse	42.68
1846	Ergonomic Fresh Mouse	3.84
1927	Ergonomic Fresh Mouse	89.04
1967	Ergonomic Fresh Mouse	20.80
1564	Ergonomic Frozen Chips	61.62
1583	Ergonomic Frozen Chips	11.31
1769	Ergonomic Frozen Chips	9.35
1930	Ergonomic Frozen Chips	53.62
1512	Ergonomic Granite Cheese	91.10
1582	Ergonomic Granite Cheese	62.36
1750	Ergonomic Granite Cheese	73.34
1559	Ergonomic Metal Cheese	24.31
1709	Ergonomic Metal Cheese	36.84
1835	Ergonomic Metal Cheese	62.14
1563	Ergonomic Plastic Gloves	86.68
1754	Ergonomic Plastic Gloves	68.80
1539	Ergonomic Rubber Sausages	39.53
1764	Ergonomic Rubber Sausages	76.13
1533	Ergonomic Soft Bacon	66.88
1760	Ergonomic Soft Bacon	88.83
1889	Ergonomic Soft Bacon	13.04
1971	Ergonomic Soft Bacon	39.53
1508	Ergonomic Steel Bike	83.19
1671	Ergonomic Steel Bike	24.42
1506	Ergonomic Wooden Table	37.40
1624	Ergonomic Wooden Table	74.96
1666	Ergonomic Wooden Table	98.51
1779	Ergonomic Wooden Table	29.69
1895	Ergonomic Wooden Table	40.02
1661	Fantastic Concrete Fish	95.67
1669	Fantastic Concrete Fish	18.62
1677	Fantastic Concrete Fish	18.74
1817	Fantastic Concrete Fish	63.57
1617	Fantastic Fresh Chips	89.06
1706	Fantastic Fresh Chips	29.45
1775	Fantastic Fresh Chips	16.01
1852	Fantastic Fresh Chips	96.98
1563	Fantastic Fresh Salad	79.43
1737	Fantastic Fresh Salad	83.85
1839	Fantastic Fresh Salad	73.13
1794	Fantastic Frozen Chicken	13.45
1848	Fantastic Frozen Chicken	78.31
1932	Fantastic Frozen Chicken	71.04
1598	Fantastic Granite Chips	87.62
1777	Fantastic Granite Chips	58.66
1779	Fantastic Granite Chips	53.78
1944	Fantastic Granite Chips	36.22
1672	Fantastic Granite Pizza	16.13
1719	Fantastic Granite Pizza	80.68
1973	Fantastic Granite Pizza	99.79
1982	Fantastic Granite Pizza	59.24
1654	Fantastic Granite Tuna	43.36
1714	Fantastic Granite Tuna	83.63
1972	Fantastic Granite Tuna	69.19
1516	Fantastic Rubber Keyboard	54.03
1524	Fantastic Rubber Keyboard	43.81
1554	Fantastic Rubber Keyboard	46.15
1826	Fantastic Rubber Keyboard	60.16
1890	Fantastic Rubber Keyboard	52.30
1972	Fantastic Rubber Keyboard	56.92
1583	Fantastic Soft Bike	22.44
1820	Fantastic Soft Bike	73.61
1992	Fantastic Soft Bike	44.61
1678	Fantastic Steel Chicken	30.40
1689	Fantastic Steel Chicken	38.86
1692	Fantastic Steel Chicken	49.06
1822	Fantastic Steel Chicken	33.63
1897	Fantastic Steel Chicken	86.40
1543	Generic Concrete Shirt	21.89
1554	Generic Concrete Shirt	38.26
1669	Generic Concrete Shirt	24.43
1720	Generic Concrete Shirt	53.85
1754	Generic Concrete Shirt	19.14
1848	Generic Concrete Shirt	46.04
1853	Generic Concrete Shirt	3.22
1857	Generic Concrete Shirt	86.96
1918	Generic Concrete Shirt	31.85
1594	Generic Fresh Car	20.42
1722	Generic Fresh Car	54.52
1734	Generic Fresh Car	27.15
1934	Generic Fresh Car	35.70
1583	Generic Fresh Chair	24.04
1740	Generic Fresh Chair	53.76
1543	Generic Fresh Keyboard	17.99
1596	Generic Fresh Keyboard	35.01
1864	Generic Fresh Keyboard	87.53
1767	Generic Granite Bacon	56.91
1817	Generic Granite Bacon	98.16
1832	Generic Granite Bacon	4.91
1520	Generic Plastic Chair	76.35
1555	Generic Plastic Chair	44.02
1702	Generic Plastic Chair	26.63
1611	Generic Rubber Keyboard	83.45
1679	Generic Rubber Keyboard	51.53
1825	Generic Rubber Keyboard	7.30
1909	Generic Rubber Keyboard	23.48
1982	Generic Rubber Keyboard	6.19
1539	Generic Rubber Salad	64.16
1608	Generic Rubber Salad	41.45
1801	Generic Rubber Salad	89.76
1876	Generic Rubber Salad	32.80
1945	Generic Rubber Salad	33.66
1611	Generic Rubber Soap	9.58
1760	Generic Rubber Soap	63.30
1912	Generic Rubber Soap	25.72
1987	Generic Rubber Soap	1.72
1515	Generic Soft Bike	30.66
1549	Generic Soft Bike	74.89
1599	Generic Soft Bike	29.56
1701	Generic Soft Bike	26.98
1836	Generic Soft Bike	26.06
1604	Generic Soft Salad	40.05
1702	Generic Soft Salad	27.89
1808	Generic Soft Salad	18.19
1861	Generic Soft Salad	98.90
1863	Generic Soft Salad	15.69
1890	Generic Soft Salad	63.14
1589	Generic Steel Keyboard	47.72
1677	Generic Steel Keyboard	82.58
1849	Generic Steel Keyboard	62.85
1857	Generic Steel Keyboard	61.18
1898	Generic Steel Keyboard	56.94
1528	Generic Wooden Gloves	71.36
1747	Generic Wooden Gloves	38.45
1782	Generic Wooden Gloves	93.69
1792	Generic Wooden Gloves	5.13
1825	Generic Wooden Gloves	76.96
1828	Generic Wooden Gloves	7.97
1897	Generic Wooden Gloves	73.69
1575	Generic Wooden Towels	27.76
1621	Generic Wooden Towels	94.52
1633	Generic Wooden Towels	95.43
1717	Generic Wooden Towels	88.43
1794	Generic Wooden Towels	27.73
1857	Generic Wooden Towels	35.02
1945	Generic Wooden Towels	41.80
1533	Gorgeous Fresh Chicken	92.30
1591	Gorgeous Fresh Chicken	20.89
1635	Gorgeous Fresh Chicken	72.35
1671	Gorgeous Fresh Chicken	43.11
1712	Gorgeous Fresh Chicken	56.52
1816	Gorgeous Fresh Chicken	47.17
1887	Gorgeous Fresh Chicken	71.37
1962	Gorgeous Fresh Chicken	69.50
1519	Gorgeous Fresh Fish	63.39
1524	Gorgeous Fresh Fish	56.36
1633	Gorgeous Fresh Fish	94.35
1728	Gorgeous Fresh Fish	32.13
1745	Gorgeous Fresh Fish	88.38
1776	Gorgeous Fresh Fish	4.64
1915	Gorgeous Fresh Fish	16.63
1942	Gorgeous Fresh Fish	34.98
1588	Gorgeous Rubber Computer	41.29
1729	Gorgeous Rubber Computer	13.78
1898	Gorgeous Rubber Computer	15.14
1590	Gorgeous Soft Car	22.28
1615	Gorgeous Soft Car	27.11
1747	Gorgeous Soft Car	35.91
1850	Gorgeous Soft Car	7.90
1749	Gorgeous Soft Cheese	71.67
1840	Gorgeous Soft Cheese	9.27
1962	Gorgeous Soft Cheese	71.78
1574	Gorgeous Soft Chicken	85.97
1799	Gorgeous Soft Chicken	76.75
1911	Gorgeous Soft Chicken	55.28
1976	Gorgeous Soft Chicken	45.45
1543	Gorgeous Soft Pants	32.50
1686	Gorgeous Soft Pants	42.13
1705	Gorgeous Soft Pants	12.74
1719	Gorgeous Soft Pants	15.08
1721	Gorgeous Soft Pants	97.98
1775	Gorgeous Soft Pants	89.69
1928	Gorgeous Soft Pants	3.38
1972	Gorgeous Soft Pants	31.17
1978	Gorgeous Soft Pants	95.35
1615	Gorgeous Soft Sausages	85.97
1835	Gorgeous Soft Sausages	15.61
1859	Gorgeous Soft Sausages	12.24
1910	Gorgeous Soft Sausages	17.16
1504	Gorgeous Soft Shoes	68.11
1505	Gorgeous Soft Shoes	55.24
1532	Gorgeous Soft Shoes	77.06
1728	Gorgeous Soft Shoes	98.76
1747	Gorgeous Soft Shoes	50.99
1964	Gorgeous Soft Shoes	64.01
1706	Gorgeous Soft Towels	62.27
1860	Gorgeous Soft Towels	57.29
1907	Gorgeous Soft Towels	27.76
1601	Gorgeous Wooden Bike	98.04
1793	Gorgeous Wooden Bike	65.21
1806	Gorgeous Wooden Bike	30.16
1819	Gorgeous Wooden Bike	30.08
1618	Gorgeous Wooden Chicken	14.30
1659	Gorgeous Wooden Chicken	88.11
1735	Gorgeous Wooden Chicken	68.92
1811	Gorgeous Wooden Chicken	57.99
1814	Handcrafted Concrete Fish	41.16
1868	Handcrafted Concrete Fish	63.98
1540	Handcrafted Concrete Pizza	51.99
1587	Handcrafted Concrete Pizza	47.88
1763	Handcrafted Concrete Pizza	60.67
1766	Handcrafted Concrete Pizza	22.92
1771	Handcrafted Concrete Pizza	22.18
1941	Handcrafted Concrete Pizza	38.25
1597	Handcrafted Cotton Chicken	85.52
1665	Handcrafted Cotton Chicken	99.96
1718	Handcrafted Cotton Chicken	68.06
1735	Handcrafted Cotton Chicken	5.09
1751	Handcrafted Cotton Chicken	2.29
1773	Handcrafted Cotton Chicken	45.73
1806	Handcrafted Cotton Chicken	13.38
1981	Handcrafted Cotton Chicken	58.43
1571	Handcrafted Fresh Mouse	81.51
1610	Handcrafted Fresh Mouse	7.96
1717	Handcrafted Fresh Mouse	5.74
1852	Handcrafted Fresh Mouse	9.07
1886	Handcrafted Fresh Mouse	11.03
1671	Handcrafted Frozen Pants	88.92
1674	Handcrafted Frozen Pants	52.72
1859	Handcrafted Frozen Pants	52.28
1980	Handcrafted Frozen Pants	68.24
1611	Handcrafted Granite Shirt	3.78
1787	Handcrafted Granite Shirt	18.18
1818	Handcrafted Granite Shirt	66.44
1953	Handcrafted Granite Shirt	55.31
1975	Handcrafted Granite Shirt	61.82
1985	Handcrafted Granite Shirt	80.42
1657	Handcrafted Metal Keyboard	75.47
1724	Handcrafted Metal Keyboard	62.48
1755	Handcrafted Metal Keyboard	95.49
1783	Handcrafted Metal Keyboard	12.05
1516	Handcrafted Plastic Hat	73.09
1567	Handcrafted Plastic Hat	28.46
1635	Handcrafted Plastic Hat	90.34
1952	Handcrafted Plastic Hat	97.63
1509	Handcrafted Plastic Hat 1	46.70
1584	Handcrafted Plastic Hat 1	23.17
1882	Handcrafted Plastic Hat 1	3.70
1918	Handcrafted Plastic Hat 1	74.66
1973	Handcrafted Plastic Hat 1	38.91
1575	Handcrafted Soft Chair	22.91
1729	Handcrafted Soft Chair	19.66
1755	Handcrafted Soft Chair	83.57
1780	Handcrafted Soft Chair	1.47
1916	Handcrafted Soft Chair	44.48
1944	Handcrafted Soft Chair	22.06
1961	Handcrafted Soft Chair	83.01
1991	Handcrafted Soft Chair	16.84
1767	Handcrafted Soft Fish	96.97
1773	Handcrafted Soft Fish	77.29
1826	Handcrafted Soft Fish	43.31
1941	Handcrafted Soft Fish	28.84
1984	Handcrafted Soft Fish	73.15
1599	Handcrafted Soft Pants	3.55
1694	Handcrafted Soft Pants	13.50
1710	Handcrafted Soft Pants	15.47
1849	Handcrafted Soft Pants	27.51
1998	Handcrafted Soft Pants	17.12
1582	Handcrafted Wooden Pizza	98.92
1650	Handcrafted Wooden Pizza	2.94
1769	Handcrafted Wooden Pizza	97.40
1797	Handcrafted Wooden Pizza	43.20
1826	Handcrafted Wooden Pizza	37.18
1854	Handcrafted Wooden Pizza	6.41
1912	Handcrafted Wooden Pizza	10.45
2001	Handcrafted Wooden Pizza	42.58
1561	Handmade Cotton Chips	35.79
1680	Handmade Cotton Chips	92.77
1691	Handmade Cotton Chips	60.47
1728	Handmade Cotton Chips	98.98
1787	Handmade Cotton Chips	13.15
1894	Handmade Cotton Chips	2.76
1977	Handmade Cotton Chips	39.26
1998	Handmade Cotton Chips	3.18
1551	Handmade Fresh Chair	14.80
1787	Handmade Fresh Chair	5.36
1915	Handmade Fresh Chair	52.10
1560	Handmade Fresh Chicken	14.32
1572	Handmade Fresh Chicken	13.44
1614	Handmade Fresh Chicken	86.64
1655	Handmade Fresh Chicken	20.23
1753	Handmade Fresh Chicken	26.61
1875	Handmade Fresh Chicken	77.13
1883	Handmade Fresh Chicken	70.62
1920	Handmade Fresh Chicken	45.99
1951	Handmade Fresh Chicken	77.75
1967	Handmade Fresh Chicken	50.44
1976	Handmade Fresh Chicken	31.99
1872	Handmade Fresh Tuna	94.91
1919	Handmade Fresh Tuna	81.73
1987	Handmade Fresh Tuna	32.44
1633	Handmade Granite Pants	63.22
1688	Handmade Granite Pants	37.76
1726	Handmade Granite Pants	59.11
1831	Handmade Granite Pants	82.87
1987	Handmade Granite Pants	96.21
1545	Handmade Plastic Bike	25.25
1565	Handmade Plastic Bike	49.64
1669	Handmade Plastic Bike	10.13
1978	Handmade Plastic Bike	61.04
1653	Handmade Rubber Chair	25.27
1724	Handmade Rubber Chair	59.63
1738	Handmade Rubber Chair	2.34
1504	Handmade Rubber Shirt	97.00
1735	Handmade Rubber Shirt	67.72
1781	Handmade Rubber Shirt	98.06
1815	Handmade Rubber Shirt	29.90
1835	Handmade Rubber Shirt	94.69
1604	Handmade Soft Towels	64.56
1757	Handmade Soft Towels	8.45
1967	Handmade Soft Towels	88.74
1556	Handmade Wooden Bacon	12.23
1978	Handmade Wooden Bacon	91.46
1641	Incredible Concrete Chicken	1.41
1647	Incredible Concrete Chicken	74.60
1656	Incredible Concrete Chicken	60.99
1672	Incredible Concrete Chicken	76.53
1730	Incredible Concrete Chicken	5.75
1509	Incredible Cotton Ball	2.07
1585	Incredible Cotton Ball	92.85
1645	Incredible Cotton Ball	66.57
1759	Incredible Cotton Ball	35.33
1763	Incredible Cotton Ball	24.97
1768	Incredible Cotton Ball	61.80
1778	Incredible Cotton Ball	56.65
1882	Incredible Cotton Ball	13.68
1938	Incredible Cotton Ball	32.07
1567	Incredible Fresh Chips	64.89
1645	Incredible Fresh Chips	6.22
1777	Incredible Fresh Chips	83.03
1820	Incredible Fresh Chips	35.25
1933	Incredible Fresh Chips	41.70
1560	Incredible Granite Car	49.24
1803	Incredible Granite Car	94.05
1895	Incredible Granite Car	71.65
1562	Incredible Metal Bike	77.62
1567	Incredible Metal Bike	33.08
1682	Incredible Metal Bike	38.42
1694	Incredible Metal Bike	85.35
1748	Incredible Metal Bike	5.96
1758	Incredible Metal Bike	31.40
1869	Incredible Metal Bike	64.92
1885	Incredible Metal Bike	84.19
1911	Incredible Metal Bike	32.06
1605	Incredible Metal Fish	83.55
1684	Incredible Metal Fish	64.59
1743	Incredible Metal Fish	85.98
1830	Incredible Metal Fish	18.63
1928	Incredible Metal Fish	17.26
1990	Incredible Metal Fish	73.57
1659	Incredible Metal Table	88.70
1671	Incredible Metal Table	28.44
1518	Incredible Metal Tuna	73.62
1711	Incredible Metal Tuna	1.01
1760	Incredible Metal Tuna	35.67
1769	Incredible Metal Tuna	18.04
1883	Incredible Metal Tuna	1.40
1889	Incredible Metal Tuna	98.35
1901	Incredible Metal Tuna	88.88
1977	Incredible Metal Tuna	72.47
1573	Incredible Rubber Bacon	28.89
1618	Incredible Rubber Bacon	25.65
1946	Incredible Rubber Bacon	62.00
1974	Incredible Rubber Bacon	33.39
1581	Incredible Rubber Chair	57.11
1709	Incredible Rubber Chair	43.58
1733	Incredible Rubber Chair	35.73
1962	Incredible Rubber Chair	83.78
1605	Incredible Rubber Shoes	67.47
1745	Incredible Rubber Shoes	41.15
1928	Incredible Rubber Shoes	90.01
1929	Incredible Rubber Shoes	33.34
1979	Incredible Rubber Shoes	33.45
1569	Incredible Steel Cheese	23.58
1697	Incredible Steel Cheese	81.75
1767	Incredible Steel Cheese	23.51
1795	Incredible Steel Cheese	79.88
1820	Incredible Steel Cheese	44.89
1516	Incredible Steel Sausages	90.01
1552	Incredible Steel Sausages	89.93
1789	Incredible Steel Sausages	39.78
1863	Incredible Steel Sausages	58.17
1992	Incredible Steel Sausages	67.28
1550	Incredible Wooden Computer	35.57
1621	Incredible Wooden Computer	64.27
1624	Incredible Wooden Computer	5.49
1631	Incredible Wooden Computer	6.45
1557	Incredible Wooden Soap	89.09
1613	Incredible Wooden Soap	94.74
1666	Incredible Wooden Soap	56.20
1789	Incredible Wooden Soap	95.98
1791	Incredible Wooden Soap	50.91
1818	Incredible Wooden Soap	11.01
1820	Incredible Wooden Soap	3.75
1843	Incredible Wooden Soap	4.71
1552	Intelligent Cotton Bacon	42.12
1643	Intelligent Cotton Bacon	98.39
1727	Intelligent Cotton Bacon	96.88
1791	Intelligent Cotton Bacon	95.98
1946	Intelligent Cotton Bacon	15.45
1510	Intelligent Fresh Mouse	47.28
1845	Intelligent Fresh Mouse	83.12
1917	Intelligent Fresh Mouse	39.67
1924	Intelligent Fresh Mouse	45.47
1934	Intelligent Fresh Mouse	91.44
2001	Intelligent Fresh Mouse	64.93
1777	Intelligent Fresh Pizza	44.00
1859	Intelligent Fresh Pizza	19.74
1876	Intelligent Fresh Pizza	12.03
1549	Intelligent Granite Chips	59.45
1614	Intelligent Granite Chips	68.99
1649	Intelligent Granite Chips	33.55
1716	Intelligent Granite Chips	82.67
1749	Intelligent Granite Chips	99.56
1821	Intelligent Granite Chips	59.75
1849	Intelligent Granite Chips	70.50
1975	Intelligent Granite Chips	66.27
1754	Intelligent Granite Sausages	71.93
1823	Intelligent Granite Sausages	76.54
1988	Intelligent Granite Sausages	97.29
1580	Intelligent Metal Chicken	24.52
1705	Intelligent Metal Chicken	69.60
1557	Intelligent Plastic Fish	45.77
1664	Intelligent Plastic Fish	49.41
1874	Intelligent Plastic Fish	69.21
1534	Intelligent Plastic Pizza	12.10
1767	Intelligent Plastic Pizza	53.65
1836	Intelligent Plastic Pizza	67.14
1655	Intelligent Rubber Chair	82.96
1776	Intelligent Rubber Chair	28.78
1983	Intelligent Rubber Chair	36.53
1646	Intelligent Rubber Pizza	94.93
1860	Intelligent Rubber Pizza	95.69
1577	Intelligent Soft Hat	59.82
1606	Intelligent Soft Hat	37.85
1716	Intelligent Soft Hat	52.12
1866	Intelligent Soft Hat	6.73
1884	Intelligent Soft Hat	84.12
1913	Intelligent Soft Hat	74.94
1989	Intelligent Soft Hat	73.38
1995	Intelligent Soft Hat	80.12
1604	Intelligent Soft Pizza	16.43
1653	Intelligent Soft Pizza	45.66
1654	Intelligent Soft Pizza	67.83
1813	Intelligent Soft Pizza	24.22
1861	Intelligent Soft Pizza	69.68
1896	Intelligent Soft Pizza	43.62
1528	Intelligent Wooden Salad	55.80
1766	Intelligent Wooden Salad	12.01
1787	Intelligent Wooden Salad	26.47
1880	Intelligent Wooden Salad	95.64
1927	Intelligent Wooden Salad	55.80
1555	Licensed Concrete Shoes	35.15
1636	Licensed Concrete Shoes	53.15
1637	Licensed Concrete Shoes	56.60
1769	Licensed Concrete Shoes	26.59
1780	Licensed Concrete Shoes	12.00
1800	Licensed Concrete Shoes	14.53
1836	Licensed Concrete Shoes	75.80
1863	Licensed Concrete Shoes	59.26
1788	Licensed Cotton Bacon	28.64
1551	Licensed Cotton Ball	32.58
1643	Licensed Cotton Ball	4.56
1894	Licensed Cotton Ball	50.07
1637	Licensed Fresh Pizza	69.24
1738	Licensed Fresh Pizza	17.78
1802	Licensed Fresh Pizza	83.91
1820	Licensed Fresh Pizza	66.26
1909	Licensed Fresh Pizza	21.44
1929	Licensed Fresh Pizza	5.86
1516	Licensed Frozen Chair	95.43
1543	Licensed Frozen Chair	4.82
1554	Licensed Frozen Chair	78.84
1604	Licensed Frozen Chair	68.53
1727	Licensed Frozen Chair	69.45
1743	Licensed Frozen Chair	69.21
1876	Licensed Frozen Chair	68.23
1590	Licensed Frozen Computer	87.69
1627	Licensed Frozen Computer	16.96
1767	Licensed Frozen Computer	94.78
1793	Licensed Frozen Computer	28.45
1915	Licensed Frozen Computer	32.39
1590	Licensed Frozen Mouse	32.06
1721	Licensed Frozen Mouse	59.84
1518	Licensed Granite Keyboard	64.14
1623	Licensed Granite Keyboard	30.80
1763	Licensed Granite Keyboard	48.20
1880	Licensed Granite Keyboard	52.55
1962	Licensed Granite Keyboard	14.88
1605	Licensed Plastic Bacon	89.49
1640	Licensed Plastic Bacon	75.64
1748	Licensed Plastic Bacon	63.26
1972	Licensed Plastic Bacon	24.29
1627	Licensed Plastic Chicken	75.47
1881	Licensed Plastic Chicken	42.34
1955	Licensed Plastic Chicken	77.47
1556	Licensed Plastic Sausages	5.68
1708	Licensed Plastic Sausages	90.19
1710	Licensed Plastic Sausages	50.14
1809	Licensed Plastic Sausages	2.75
1833	Licensed Plastic Sausages	55.07
1851	Licensed Plastic Sausages	6.73
1621	Licensed Plastic Shirt	28.67
1685	Licensed Plastic Shirt	18.21
1716	Licensed Plastic Shirt	59.59
1813	Licensed Plastic Shirt	26.94
1899	Licensed Plastic Shirt	42.88
1971	Licensed Plastic Shirt	32.36
1616	Licensed Rubber Mouse	41.40
1725	Licensed Rubber Mouse	42.12
1915	Licensed Rubber Mouse	35.64
1584	Licensed Soft Computer	46.38
1778	Licensed Soft Computer	15.93
1834	Licensed Soft Computer	64.38
1850	Licensed Soft Computer	17.44
1853	Licensed Soft Computer	48.42
1886	Licensed Soft Computer	27.66
1538	Licensed Soft Keyboard	14.88
1684	Licensed Soft Keyboard	11.09
1705	Licensed Soft Keyboard	51.46
1790	Licensed Soft Keyboard	23.10
1922	Licensed Soft Keyboard	16.60
1935	Licensed Soft Keyboard	20.13
1980	Licensed Soft Keyboard	22.60
1518	Licensed Steel Bacon	21.02
1609	Licensed Steel Bacon	90.31
1677	Licensed Steel Bacon	49.01
1709	Licensed Steel Bacon	18.23
1817	Licensed Steel Bacon	6.23
1836	Licensed Steel Bacon	68.74
1893	Licensed Steel Bacon	14.60
1908	Licensed Steel Bacon	41.77
1969	Licensed Steel Bacon	80.30
1584	Licensed Steel Fish	90.63
1808	Licensed Steel Fish	27.86
1841	Licensed Steel Fish	81.16
1934	Licensed Steel Fish	49.78
1609	Licensed Steel Shoes	47.77
1615	Licensed Steel Shoes	9.75
1896	Licensed Wooden Cheese	29.25
1917	Licensed Wooden Cheese	16.83
1974	Licensed Wooden Cheese	22.44
1572	Licensed Wooden Sausages	91.62
1719	Licensed Wooden Sausages	21.18
1843	Licensed Wooden Sausages	22.43
1912	Licensed Wooden Sausages	33.19
1601	Licensed Wooden Towels	4.07
1696	Licensed Wooden Towels	49.81
1746	Licensed Wooden Towels	80.77
1766	Licensed Wooden Towels	69.44
1782	Licensed Wooden Towels	17.29
1872	Licensed Wooden Towels	42.86
1502	Practical Concrete Salad	23.57
1570	Practical Concrete Salad	33.28
1627	Practical Concrete Salad	56.43
1669	Practical Concrete Salad	90.91
1509	Practical Cotton Gloves	9.26
1556	Practical Cotton Gloves	88.51
1560	Practical Cotton Gloves	12.62
1708	Practical Cotton Gloves	22.33
1770	Practical Cotton Gloves	34.85
1830	Practical Cotton Gloves	16.26
1873	Practical Cotton Gloves	9.62
1960	Practical Cotton Gloves	74.75
1693	Practical Cotton Keyboard	90.94
1764	Practical Cotton Keyboard	73.06
1952	Practical Cotton Keyboard	27.59
1967	Practical Cotton Keyboard	11.78
1771	Practical Fresh Chips	7.98
1801	Practical Fresh Chips	55.78
1979	Practical Fresh Keyboard	4.05
1521	Practical Metal Hat	18.03
1622	Practical Metal Hat	22.02
1707	Practical Metal Hat	48.73
1723	Practical Metal Hat	47.78
1829	Practical Metal Hat	42.90
1551	Practical Plastic Mouse	66.92
1781	Practical Plastic Mouse	39.04
1887	Practical Plastic Mouse	27.59
1533	Practical Plastic Shirt	13.18
1685	Practical Plastic Shirt	29.64
1691	Practical Plastic Shirt	35.64
1700	Practical Plastic Shirt	93.69
1851	Practical Plastic Shirt	25.30
1884	Practical Plastic Shirt	59.36
1899	Practical Plastic Shirt	92.75
1912	Practical Plastic Shirt	96.88
1950	Practical Plastic Shirt	47.94
1514	Practical Soft Bacon	15.37
1595	Practical Soft Bacon	30.89
1744	Practical Soft Bacon	75.24
1930	Practical Soft Bacon	65.86
1964	Practical Soft Bacon	9.81
1508	Practical Soft Shirt	60.72
1511	Practical Soft Shirt	94.23
1546	Practical Soft Shirt	68.73
1663	Practical Soft Shirt	94.75
1667	Practical Soft Shirt	62.45
1693	Practical Soft Shirt	52.22
1807	Practical Soft Shirt	30.11
1913	Practical Soft Shirt	14.34
1982	Practical Soft Shirt	61.38
1987	Practical Soft Shirt	53.62
2000	Practical Soft Shirt	36.96
1564	Refined Concrete Pants	18.86
1714	Refined Concrete Pants	13.96
1758	Refined Concrete Pants	31.58
1877	Refined Concrete Pants	29.10
1907	Refined Concrete Pants	93.96
1567	Refined Cotton Soap	5.03
1651	Refined Cotton Soap	34.98
1751	Refined Cotton Soap	77.61
1752	Refined Cotton Soap	51.77
1851	Refined Cotton Soap	59.64
1539	Refined Fresh Chair	28.44
1647	Refined Fresh Chair	43.48
1680	Refined Fresh Chair	59.68
1893	Refined Fresh Chair	79.23
1701	Refined Fresh Chips	20.96
1778	Refined Fresh Chips	20.00
1825	Refined Fresh Chips	35.21
1842	Refined Fresh Chips	70.54
1879	Refined Fresh Chips	29.12
1888	Refined Fresh Chips	57.85
2001	Refined Fresh Chips	3.42
1526	Refined Rubber Pants	42.73
1655	Refined Rubber Pants	6.91
1662	Refined Rubber Pants	63.61
1801	Refined Rubber Pants	65.82
1844	Refined Rubber Pants	67.89
1901	Refined Rubber Pants	93.38
1962	Refined Rubber Pants	39.88
1742	Refined Steel Fish	80.82
1943	Refined Steel Fish	15.09
1944	Refined Steel Fish	95.50
1973	Refined Steel Fish	90.04
1548	Refined Steel Mouse	90.22
1715	Refined Steel Mouse	64.28
1747	Refined Steel Mouse	32.37
1768	Refined Steel Mouse	88.01
1799	Refined Steel Mouse	26.29
1882	Refined Steel Mouse	7.90
1545	Refined Wooden Car	70.25
1579	Refined Wooden Car	63.18
1702	Refined Wooden Car	47.11
1917	Refined Wooden Car	99.65
1946	Refined Wooden Car	30.81
1976	Refined Wooden Car	84.45
1577	Refined Wooden Table	23.15
1738	Refined Wooden Table	72.35
1825	Refined Wooden Table	18.32
1856	Refined Wooden Table	42.45
1899	Refined Wooden Table	85.81
1581	Rustic Concrete Chair	51.43
1605	Rustic Concrete Chair	67.02
1627	Rustic Concrete Chair	34.23
1665	Rustic Concrete Chair	97.48
1777	Rustic Concrete Chair	67.86
1812	Rustic Concrete Chair	95.77
1890	Rustic Concrete Chair	54.75
1946	Rustic Concrete Chair	72.13
1606	Rustic Concrete Shirt	75.71
1704	Rustic Concrete Shirt	24.68
1867	Rustic Concrete Shirt	97.40
2001	Rustic Concrete Shirt	35.35
1672	Rustic Frozen Bacon	65.16
1748	Rustic Frozen Bacon	64.84
1870	Rustic Frozen Bacon	97.60
1926	Rustic Frozen Bacon	69.08
1984	Rustic Frozen Bacon	36.80
1603	Rustic Frozen Ball	94.96
1724	Rustic Frozen Ball	66.67
1901	Rustic Frozen Ball	59.82
1916	Rustic Frozen Ball	89.78
1566	Rustic Frozen Chair	2.15
1664	Rustic Frozen Chair	94.45
1755	Rustic Frozen Chair	46.93
1827	Rustic Frozen Chair	93.48
1972	Rustic Frozen Chair	82.97
1678	Rustic Granite Cheese	3.57
1894	Rustic Granite Cheese	32.33
1588	Rustic Metal Chips	19.27
1673	Rustic Metal Chips	89.20
1633	Rustic Metal Sausages	62.56
1766	Rustic Metal Sausages	93.33
1836	Rustic Metal Sausages	89.66
1603	Rustic Rubber Fish	40.77
1638	Rustic Rubber Fish	46.28
1665	Rustic Rubber Fish	21.51
1709	Rustic Rubber Fish	4.56
1737	Rustic Rubber Fish	37.08
1907	Rustic Rubber Fish	97.91
1561	Rustic Soft Chips	34.59
1798	Rustic Soft Chips	43.18
1875	Rustic Soft Chips	63.43
1903	Rustic Soft Chips	52.39
1921	Rustic Soft Chips	1.89
1603	Rustic Wooden Hat	48.57
1711	Rustic Wooden Hat	69.91
1893	Rustic Wooden Hat	73.81
1654	Sleek Cotton Cheese	89.90
1688	Sleek Cotton Cheese	23.11
1675	Sleek Cotton Soap	96.29
1764	Sleek Cotton Soap	72.70
1794	Sleek Cotton Soap	95.93
1856	Sleek Cotton Soap	11.91
1858	Sleek Cotton Soap	19.23
1908	Sleek Cotton Soap	32.83
1625	Sleek Fresh Bacon	76.74
1529	Sleek Fresh Keyboard	82.13
1537	Sleek Fresh Keyboard	42.79
1762	Sleek Fresh Keyboard	43.74
1770	Sleek Fresh Keyboard	68.11
1778	Sleek Fresh Keyboard	97.62
1790	Sleek Fresh Keyboard	37.94
1834	Sleek Fresh Keyboard	47.56
1837	Sleek Fresh Keyboard	68.12
1848	Sleek Fresh Keyboard	71.92
1644	Sleek Frozen Chicken	47.85
1675	Sleek Frozen Chicken	65.22
1792	Sleek Frozen Chicken	12.98
1916	Sleek Frozen Chicken	56.42
1532	Sleek Granite Car	70.59
1540	Sleek Granite Car	97.52
1640	Sleek Granite Car	41.99
1816	Sleek Granite Car	37.17
1848	Sleek Granite Car	74.77
1545	Sleek Granite Fish	42.77
1592	Sleek Granite Fish	53.10
1663	Sleek Granite Fish	89.53
1674	Sleek Granite Fish	7.28
1847	Sleek Granite Fish	20.09
1923	Sleek Granite Fish	85.06
1971	Sleek Granite Fish	84.64
1989	Sleek Granite Fish	64.71
1595	Sleek Granite Tuna	97.90
1597	Sleek Granite Tuna	23.98
1738	Sleek Granite Tuna	44.48
1859	Sleek Granite Tuna	61.63
1936	Sleek Granite Tuna	58.67
1937	Sleek Granite Tuna	76.10
1969	Sleek Granite Tuna	75.24
1982	Sleek Granite Tuna	96.68
1672	Sleek Metal Soap	50.26
1702	Sleek Metal Soap	94.22
1743	Sleek Metal Soap	95.52
1768	Sleek Metal Soap	15.56
1818	Sleek Metal Soap	46.90
1573	Small Cotton Salad	67.98
1579	Small Cotton Salad	56.62
1588	Small Cotton Salad	56.87
1635	Small Cotton Salad	82.33
1666	Small Cotton Salad	89.02
1724	Small Cotton Salad	28.26
1750	Small Cotton Salad	18.94
1865	Small Cotton Salad	39.05
1973	Small Cotton Salad	56.25
1560	Small Fresh Car	72.67
1645	Small Fresh Car	6.24
1789	Small Fresh Car	60.51
1937	Small Fresh Car	86.72
1983	Small Fresh Car	64.70
1733	Small Frozen Bike	87.81
1737	Small Frozen Bike	1.93
1745	Small Frozen Bike	8.32
1768	Small Frozen Bike	3.19
1818	Small Frozen Bike	13.33
1897	Small Frozen Bike	59.79
1944	Small Frozen Bike	30.25
1950	Small Frozen Bike	20.42
1683	Small Plastic Bike	36.57
1838	Small Plastic Bike	76.20
1844	Small Plastic Bike	34.30
1901	Small Plastic Bike	69.37
1524	Small Plastic Cheese	28.84
1611	Small Plastic Cheese	28.67
1858	Small Plastic Cheese	2.05
1581	Small Soft Gloves	37.20
1612	Small Soft Gloves	8.39
1834	Small Soft Gloves	37.69
1876	Small Soft Gloves	53.07
1915	Small Soft Gloves	15.44
1958	Small Soft Gloves	93.32
1986	Small Soft Gloves	18.30
2001	Small Soft Gloves	41.24
1554	Small Soft Pizza	39.45
1594	Small Soft Pizza	95.66
1650	Small Soft Pizza	86.96
1710	Small Soft Pizza	35.27
1772	Small Soft Pizza	3.77
1822	Small Soft Pizza	61.09
1568	Tasty Concrete Shoes	23.92
1633	Tasty Concrete Shoes	89.64
1683	Tasty Concrete Shoes	95.06
1712	Tasty Concrete Shoes	25.86
1715	Tasty Concrete Shoes	95.87
1787	Tasty Concrete Shoes	21.44
1904	Tasty Concrete Shoes	48.64
1934	Tasty Concrete Shoes	51.27
2001	Tasty Concrete Shoes	68.75
1737	Tasty Concrete Tuna	82.57
1754	Tasty Concrete Tuna	22.67
1783	Tasty Concrete Tuna	72.18
1999	Tasty Concrete Tuna	19.03
1594	Tasty Cotton Keyboard	39.84
1601	Tasty Cotton Keyboard	60.99
1655	Tasty Cotton Keyboard	87.66
1662	Tasty Cotton Keyboard	46.06
1702	Tasty Cotton Keyboard	64.12
1838	Tasty Cotton Keyboard	42.29
1852	Tasty Cotton Keyboard	28.29
1859	Tasty Cotton Keyboard	57.98
1966	Tasty Cotton Keyboard	77.32
1594	Tasty Fresh Computer	43.21
1609	Tasty Fresh Computer	57.04
1644	Tasty Fresh Computer	13.81
1851	Tasty Fresh Computer	42.61
1892	Tasty Fresh Computer	67.23
1906	Tasty Fresh Computer	23.25
1960	Tasty Fresh Computer	14.07
1754	Tasty Fresh Salad	35.91
1871	Tasty Fresh Salad	60.49
1893	Tasty Fresh Salad	84.27
1553	Tasty Granite Cheese	43.13
1793	Tasty Granite Cheese	45.46
1972	Tasty Granite Cheese	43.92
1653	Tasty Metal Keyboard	11.09
1675	Tasty Metal Keyboard	92.63
1722	Tasty Metal Keyboard	23.92
1820	Tasty Metal Keyboard	44.35
1884	Tasty Metal Keyboard	28.14
1947	Tasty Metal Keyboard	8.76
1524	Tasty Metal Pants	17.96
1558	Tasty Metal Pants	74.70
1632	Tasty Metal Pants	44.42
1676	Tasty Metal Pants	42.62
1686	Tasty Metal Pants	29.25
1706	Tasty Metal Pants	77.39
1726	Tasty Metal Pants	74.64
1812	Tasty Metal Pants	30.50
1973	Tasty Metal Pants	65.58
1982	Tasty Metal Pants	87.19
1642	Tasty Rubber Bike	86.91
1730	Tasty Rubber Bike	12.32
1733	Tasty Rubber Bike	70.50
1745	Tasty Rubber Bike	72.55
1765	Tasty Rubber Bike	49.74
1832	Tasty Rubber Bike	92.49
1799	Tasty Rubber Chips	39.76
1939	Tasty Rubber Chips	20.48
1587	Tasty Soft Hat	99.61
1679	Tasty Soft Hat	38.24
1781	Tasty Soft Hat	52.27
1940	Tasty Soft Hat	85.29
1531	Tasty Soft Shoes	15.75
1572	Tasty Soft Shoes	13.79
1621	Tasty Soft Shoes	58.51
1863	Tasty Soft Shoes	59.40
1934	Tasty Soft Shoes	22.11
1960	Tasty Soft Shoes	13.66
1992	Tasty Soft Shoes	38.36
1502	Tasty Soft Tuna	84.52
1633	Tasty Soft Tuna	59.57
1666	Tasty Soft Tuna	60.28
1801	Tasty Soft Tuna	41.50
1810	Tasty Soft Tuna	60.55
1976	Tasty Soft Tuna	28.92
1820	Tasty Steel Chips	92.57
1795	Tasty Steel Table	77.35
1847	Tasty Steel Table	91.61
1974	Tasty Steel Table	97.62
1995	Tasty Steel Table	50.06
1523	Tasty Wooden Chips	38.10
1529	Tasty Wooden Chips	34.48
1530	Tasty Wooden Chips	55.45
1554	Tasty Wooden Chips	11.54
1748	Tasty Wooden Chips	71.81
1811	Tasty Wooden Chips	93.41
1881	Tasty Wooden Chips	58.59
1884	Tasty Wooden Chips	23.89
1910	Tasty Wooden Chips	27.37
1937	Tasty Wooden Chips	10.91
1979	Tasty Wooden Chips	90.08
1533	Tasty Wooden Gloves	38.49
1538	Tasty Wooden Gloves	67.54
1540	Tasty Wooden Gloves	48.98
1556	Tasty Wooden Gloves	31.62
1792	Tasty Wooden Gloves	13.68
1795	Tasty Wooden Gloves	12.92
1817	Tasty Wooden Gloves	24.89
1912	Tasty Wooden Gloves	41.33
1986	Tasty Wooden Gloves	71.55
1987	Tasty Wooden Gloves	3.47
1699	Unbranded Cotton Pizza	16.06
1729	Unbranded Cotton Pizza	36.58
1783	Unbranded Cotton Pizza	9.81
1934	Unbranded Cotton Pizza	27.46
1959	Unbranded Cotton Pizza	82.95
1524	Unbranded Fresh Pizza	12.77
1612	Unbranded Fresh Pizza	28.36
1634	Unbranded Fresh Pizza	33.27
1678	Unbranded Fresh Pizza	90.37
1794	Unbranded Fresh Pizza	82.30
1830	Unbranded Fresh Pizza	70.39
1844	Unbranded Fresh Pizza	65.98
1854	Unbranded Fresh Pizza	54.16
1987	Unbranded Fresh Pizza	94.43
1893	Unbranded Frozen Keyboard	15.94
1802	Unbranded Granite Bike	67.55
1858	Unbranded Granite Bike	49.06
1876	Unbranded Granite Bike	37.85
1513	Unbranded Metal Fish	52.90
1555	Unbranded Metal Fish	20.15
1655	Unbranded Metal Fish	78.68
1732	Unbranded Metal Fish	52.38
1735	Unbranded Metal Fish	65.72
1802	Unbranded Metal Fish	72.04
1808	Unbranded Metal Fish	1.49
1516	Tasty Metal Hat	179.99
1682	Tasty Metal Hat	105.64
1727	Tasty Metal Hat	162.51
1797	Tasty Metal Hat	186.69
1827	Tasty Metal Hat	187.54
1884	Tasty Metal Hat	91.07
1888	Tasty Metal Hat	148.20
1820	Unbranded Metal Fish 1	26.54
1908	Unbranded Metal Fish 1	66.51
1579	Unbranded Metal Hat	60.87
1804	Unbranded Metal Hat	83.47
1925	Unbranded Metal Hat	75.03
1855	Unbranded Steel Chair	72.88
1871	Unbranded Steel Chair	9.62
1993	Unbranded Steel Chair	68.92
1507	Tasty Metal Ball	99.90
1593	Tasty Metal Ball	119.09
1616	Tasty Metal Ball	180.92
1712	Tasty Metal Ball	141.39
1763	Tasty Metal Ball	142.39
1779	Tasty Metal Ball	97.72
1844	Tasty Metal Ball	159.69
1892	Tasty Metal Hat	114.78
1996	Tasty Metal Hat	106.09
1510	Gorgeous Steel Computer	168.99
1546	Gorgeous Steel Computer	107.02
1612	Gorgeous Steel Computer	161.47
1632	Gorgeous Steel Computer	112.90
1664	Gorgeous Steel Computer	149.26
1711	Gorgeous Steel Computer	115.17
1749	Gorgeous Steel Computer	145.77
1764	Gorgeous Steel Computer	115.53
1781	Gorgeous Steel Computer	99.89
1915	Gorgeous Steel Computer	124.71
1921	Gorgeous Steel Computer	122.52
1600	Rustic Rubber Shirt	12.00
1502	Cement M500	30.00
1502	Ceramic Tiles	55.00
1502	Practical Fresh Keyboard	5.00
1584	Ergonomic Frozen Chips	173.82
1584	Fantastic Soft Bike	81.42
1584	Generic Rubber Keyboard	581.10
1584	Handmade Rubber Shirt	434.04
1584	Rustic Concrete Chair	101.46
1584	Small Plastic Cheese	230.40
1584	Tasty Granite Cheese	485.16
1744	Gorgeous Wooden Chicken	43.68
1744	Rustic Metal Sausages	957.18
1744	Tasty Soft Hat	1103.34
\.


--
-- TOC entry 4958 (class 0 OID 0)
-- Dependencies: 222
-- Name: invoice_invoice_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.invoice_invoice_id_seq', 1631, true);


--
-- TOC entry 4959 (class 0 OID 0)
-- Dependencies: 218
-- Name: storage_storage_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.storage_storage_id_seq', 2001, true);


--
-- TOC entry 4777 (class 2606 OID 16545)
-- Name: invoice invoice_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_pkey PRIMARY KEY (invoice_id);


--
-- TOC entry 4780 (class 2606 OID 24610)
-- Name: list_entry list_entry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.list_entry
    ADD CONSTRAINT list_entry_pkey PRIMARY KEY (product_name, invoice_id);


--
-- TOC entry 4766 (class 2606 OID 16537)
-- Name: product product_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product
    ADD CONSTRAINT product_pkey PRIMARY KEY (product_name);


--
-- TOC entry 4746 (class 2606 OID 16662)
-- Name: counterparty provider_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counterparty
    ADD CONSTRAINT provider_pkey PRIMARY KEY (name);


--
-- TOC entry 4759 (class 2606 OID 16526)
-- Name: storage_keeper storage_keeper_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage_keeper
    ADD CONSTRAINT storage_keeper_pkey PRIMARY KEY (phone_number);


--
-- TOC entry 4755 (class 2606 OID 16521)
-- Name: storage storage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage
    ADD CONSTRAINT storage_pkey PRIMARY KEY (storage_id);


--
-- TOC entry 4785 (class 2606 OID 24608)
-- Name: storage_product storage_product_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage_product
    ADD CONSTRAINT storage_product_pkey PRIMARY KEY (product_name, storage_id);


--
-- TOC entry 4768 (class 2606 OID 16642)
-- Name: product unique_product_name; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product
    ADD CONSTRAINT unique_product_name UNIQUE (product_name);


--
-- TOC entry 4748 (class 2606 OID 24590)
-- Name: counterparty unique_provider_email; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counterparty
    ADD CONSTRAINT unique_provider_email UNIQUE (email);


--
-- TOC entry 4750 (class 2606 OID 16650)
-- Name: counterparty unique_provider_name; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counterparty
    ADD CONSTRAINT unique_provider_name UNIQUE (name);


--
-- TOC entry 4752 (class 2606 OID 16629)
-- Name: counterparty unique_provider_phone_number; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counterparty
    ADD CONSTRAINT unique_provider_phone_number UNIQUE (phone_number);


--
-- TOC entry 4761 (class 2606 OID 24592)
-- Name: storage_keeper unique_storage_keeper_email; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage_keeper
    ADD CONSTRAINT unique_storage_keeper_email UNIQUE (email);


--
-- TOC entry 4763 (class 2606 OID 16631)
-- Name: storage_keeper unique_storage_keeper_phone_number; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage_keeper
    ADD CONSTRAINT unique_storage_keeper_phone_number UNIQUE (phone_number);


--
-- TOC entry 4744 (class 1259 OID 33073)
-- Name: idx_counterparty_counterparty_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_counterparty_counterparty_name ON public.counterparty USING btree (name);


--
-- TOC entry 4756 (class 1259 OID 33093)
-- Name: idx_hash_first_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_hash_first_name ON public.storage_keeper USING hash (first_name);


--
-- TOC entry 4757 (class 1259 OID 33094)
-- Name: idx_hash_last_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_hash_last_name ON public.storage_keeper USING hash (last_name);


--
-- TOC entry 4769 (class 1259 OID 33072)
-- Name: idx_invoice_counterparty_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoice_counterparty_name ON public.invoice USING btree (counterparty_name);


--
-- TOC entry 4770 (class 1259 OID 33084)
-- Name: idx_invoice_invoice_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoice_invoice_date ON public.invoice USING btree (date);


--
-- TOC entry 4771 (class 1259 OID 33075)
-- Name: idx_invoice_invoice_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoice_invoice_id ON public.invoice USING btree (storage_id);


--
-- TOC entry 4772 (class 1259 OID 33106)
-- Name: idx_invoice_storage_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoice_storage_id ON public.invoice USING btree (storage_id);


--
-- TOC entry 4773 (class 1259 OID 33082)
-- Name: idx_invoice_total_price; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoice_total_price ON public.invoice USING btree (total_price);


--
-- TOC entry 4774 (class 1259 OID 33081)
-- Name: idx_invoice_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoice_type ON public.invoice USING btree (type);


--
-- TOC entry 4775 (class 1259 OID 33095)
-- Name: idx_invoice_year; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invoice_year ON public.invoice USING btree (EXTRACT(year FROM date));


--
-- TOC entry 4778 (class 1259 OID 33076)
-- Name: idx_list_entry_product_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_list_entry_product_name ON public.list_entry USING btree (product_name);


--
-- TOC entry 4764 (class 1259 OID 33077)
-- Name: idx_product_product_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_product_product_name ON public.product USING btree (product_name);


--
-- TOC entry 4781 (class 1259 OID 41272)
-- Name: idx_storage_product_count; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_storage_product_count ON public.storage_product USING btree (count);


--
-- TOC entry 4782 (class 1259 OID 41273)
-- Name: idx_storage_product_name_count; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_storage_product_name_count ON public.storage_product USING btree (product_name, count);


--
-- TOC entry 4783 (class 1259 OID 33107)
-- Name: idx_storage_product_storage_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_storage_product_storage_id ON public.storage_product USING btree (storage_id);


--
-- TOC entry 4753 (class 1259 OID 33108)
-- Name: idx_storage_storage_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_storage_storage_id ON public.storage USING btree (storage_id);


--
-- TOC entry 4795 (class 2620 OID 33052)
-- Name: list_entry check_stock_before_insert_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER check_stock_before_insert_trigger BEFORE INSERT ON public.list_entry FOR EACH ROW EXECUTE FUNCTION public.check_storage_stock();


--
-- TOC entry 4794 (class 2620 OID 33048)
-- Name: product prevent_product_deletion_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prevent_product_deletion_trigger BEFORE DELETE ON public.product FOR EACH ROW EXECUTE FUNCTION public.prevent_product_deletion();


--
-- TOC entry 4798 (class 2620 OID 33046)
-- Name: storage_product trg_check_product_integrity; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_check_product_integrity BEFORE INSERT OR DELETE OR UPDATE ON public.storage_product FOR EACH ROW EXECUTE FUNCTION public.check_product_integrity();


--
-- TOC entry 4796 (class 2620 OID 41265)
-- Name: list_entry trigger_update_total_price; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_total_price AFTER INSERT OR UPDATE ON public.list_entry FOR EACH ROW EXECUTE FUNCTION public.update_total_price();


--
-- TOC entry 4797 (class 2620 OID 33056)
-- Name: list_entry update_last_price_after_update_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_last_price_after_update_trigger AFTER INSERT OR UPDATE ON public.list_entry FOR EACH ROW EXECUTE FUNCTION public.update_last_price();


--
-- TOC entry 4787 (class 2606 OID 24641)
-- Name: invoice invoice_counterparty_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_counterparty_name_fkey FOREIGN KEY (counterparty_name) REFERENCES public.counterparty(name) ON UPDATE CASCADE NOT VALID;


--
-- TOC entry 4788 (class 2606 OID 16556)
-- Name: invoice invoice_storage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_storage_id_fkey FOREIGN KEY (storage_id) REFERENCES public.storage(storage_id) ON DELETE CASCADE;


--
-- TOC entry 4789 (class 2606 OID 41249)
-- Name: invoice invoice_storage_keeper_phone_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_storage_keeper_phone_fkey FOREIGN KEY (storage_keeper_phone) REFERENCES public.storage_keeper(phone_number) ON UPDATE CASCADE ON DELETE SET NULL NOT VALID;


--
-- TOC entry 4790 (class 2606 OID 16570)
-- Name: list_entry list_entry_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.list_entry
    ADD CONSTRAINT list_entry_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoice(invoice_id) ON DELETE CASCADE;


--
-- TOC entry 4791 (class 2606 OID 16663)
-- Name: list_entry list_entry_product_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.list_entry
    ADD CONSTRAINT list_entry_product_name_fkey FOREIGN KEY (product_name) REFERENCES public.product(product_name) ON DELETE RESTRICT;


--
-- TOC entry 4786 (class 2606 OID 24636)
-- Name: storage_keeper storage_keeper_storage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage_keeper
    ADD CONSTRAINT storage_keeper_storage_id_fkey FOREIGN KEY (storage_id) REFERENCES public.storage(storage_id) ON DELETE RESTRICT NOT VALID;


--
-- TOC entry 4792 (class 2606 OID 16668)
-- Name: storage_product storage_product_product_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage_product
    ADD CONSTRAINT storage_product_product_name_fkey FOREIGN KEY (product_name) REFERENCES public.product(product_name) ON DELETE RESTRICT;


--
-- TOC entry 4793 (class 2606 OID 16673)
-- Name: storage_product storage_product_storage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage_product
    ADD CONSTRAINT storage_product_storage_id_fkey FOREIGN KEY (storage_id) REFERENCES public.storage(storage_id) ON DELETE RESTRICT;


-- Completed on 2025-04-26 13:34:41

--
-- PostgreSQL database dump complete
--

