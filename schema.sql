--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.4

-- Started on 2026-09-28 23:57:11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 2 (class 3079 OID 16439)
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- TOC entry 5097 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 231 (class 1259 OID 25018)
-- Name: academic_terms; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.academic_terms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_year text NOT NULL,
    semester text NOT NULL,
    is_current boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT academic_terms_school_year_check CHECK ((btrim(school_year) <> ''::text)),
    CONSTRAINT academic_terms_semester_check CHECK ((btrim(semester) <> ''::text))
);


ALTER TABLE public.academic_terms OWNER TO neondb_owner;

--
-- TOC entry 227 (class 1259 OID 16606)
-- Name: attendance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attendance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    campus_id uuid NOT NULL,
    attendance_date date NOT NULL,
    time_in timestamp without time zone,
    time_out timestamp without time zone,
    latitude numeric(10,8),
    longitude numeric(11,8),
    status character varying(20) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    latitude_in numeric,
    longitude_in numeric,
    latitude_out numeric,
    longitude_out numeric,
    outside_since timestamp without time zone,
    class_schedule_id uuid,
    CONSTRAINT attendance_status_check CHECK (((status)::text = ANY ((ARRAY['present'::character varying, 'late'::character varying, 'absent'::character varying, 'timeout'::character varying])::text[])))
);


ALTER TABLE public.attendance OWNER TO neondb_owner;

--
-- TOC entry 223 (class 1259 OID 16540)
-- Name: campuses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.campuses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campus_code character varying(20) NOT NULL,
    campus_name character varying(100) NOT NULL,
    latitude numeric(10,7) NOT NULL,
    longitude numeric(10,7) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    boundary_coordinates jsonb,
    check_in_start time without time zone,
    late_after time without time zone
);


ALTER TABLE public.campuses OWNER TO neondb_owner;

--
-- TOC entry 229 (class 1259 OID 24981)
-- Name: class_schedules; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.class_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    course text NOT NULL,
    year_level text NOT NULL,
    section text NOT NULL,
    subject text NOT NULL,
    weekday smallint NOT NULL,
    start_time time without time zone NOT NULL,
    late_after time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    teacher_user_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    instructor_name text,
    academic_term_id uuid NOT NULL,
    is_archived boolean DEFAULT false NOT NULL,
    CONSTRAINT class_schedules_check CHECK (((start_time < late_after) AND (late_after < end_time))),
    CONSTRAINT class_schedules_weekday_check CHECK (((weekday >= 0) AND (weekday <= 6)))
);


ALTER TABLE public.class_schedules OWNER TO neondb_owner;

--
-- TOC entry 230 (class 1259 OID 25008)
-- Name: courses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.courses (
    course_code text NOT NULL,
    course_name text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT courses_course_code_check CHECK ((btrim(course_code) <> ''::text)),
    CONSTRAINT courses_course_name_check CHECK ((btrim(course_name) <> ''::text))
);


ALTER TABLE public.courses OWNER TO neondb_owner;

--
-- TOC entry 228 (class 1259 OID 16633)
-- Name: notifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    type character varying(30) NOT NULL,
    title character varying(150) NOT NULL,
    message text NOT NULL,
    read_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT notifications_type_check CHECK (((type)::text = ANY ((ARRAY['Attendance'::character varying, 'Reminder'::character varying, 'System'::character varying])::text[])))
);


ALTER TABLE public.notifications OWNER TO neondb_owner;

--
-- TOC entry 224 (class 1259 OID 16549)
-- Name: parents; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.parents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    first_name character varying(100) NOT NULL,
    middle_name character varying(100),
    last_name character varying(100) NOT NULL,
    contact_number character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.parents OWNER TO neondb_owner;

--
-- TOC entry 222 (class 1259 OID 16513)
-- Name: registration_requests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.registration_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying(255) NOT NULL,
    first_name character varying(100) NOT NULL,
    middle_name character varying(100),
    last_name character varying(100) NOT NULL,
    requested_role_id integer NOT NULL,
    student_number character varying(20),
    email_verified boolean DEFAULT false,
    status character varying(20) DEFAULT 'pending'::character varying,
    requested_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    reviewed_at timestamp without time zone,
    reviewed_by uuid,
    course character varying(100),
    year_level character varying(10),
    section character varying(10),
    employee_number character varying(30),
    contact_number character varying(20),
    child_student_number character varying(30),
    password_hash character varying(255),
    CONSTRAINT registration_requests_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying])::text[])))
);


ALTER TABLE public.registration_requests OWNER TO neondb_owner;

--
-- TOC entry 220 (class 1259 OID 16490)
-- Name: roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roles (
    id integer NOT NULL,
    name character varying(30) NOT NULL
);


ALTER TABLE public.roles OWNER TO neondb_owner;

--
-- TOC entry 219 (class 1259 OID 16489)
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roles_id_seq OWNER TO neondb_owner;

--
-- TOC entry 5098 (class 0 OID 0)
-- Dependencies: 219
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- TOC entry 226 (class 1259 OID 16579)
-- Name: students; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.students (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    parent_id uuid,
    student_number character varying(30) NOT NULL,
    first_name character varying(100) NOT NULL,
    middle_name character varying(100),
    last_name character varying(100) NOT NULL,
    course character varying(100),
    year_level character varying(20),
    section character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.students OWNER TO neondb_owner;

--
-- TOC entry 225 (class 1259 OID 16563)
-- Name: teachers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.teachers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    employee_number character varying(30) NOT NULL,
    first_name character varying(100) NOT NULL,
    middle_name character varying(100),
    last_name character varying(100) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.teachers OWNER TO neondb_owner;

--
-- TOC entry 221 (class 1259 OID 16498)
-- Name: user_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_roles (
    user_id uuid NOT NULL,
    role_id integer NOT NULL
);


ALTER TABLE public.user_roles OWNER TO neondb_owner;

--
-- TOC entry 218 (class 1259 OID 16476)
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying(255) NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying,
    email_verified boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    password_hash text,
    CONSTRAINT users_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying, 'suspended'::character varying])::text[])))
);


ALTER TABLE public.users OWNER TO neondb_owner;

--
-- TOC entry 4832 (class 2604 OID 16493)
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- TOC entry 4930 (class 2606 OID 25029)
-- Name: academic_terms academic_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.academic_terms
    ADD CONSTRAINT academic_terms_pkey PRIMARY KEY (id);


--
-- TOC entry 4932 (class 2606 OID 25031)
-- Name: academic_terms academic_terms_school_year_semester_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.academic_terms
    ADD CONSTRAINT academic_terms_school_year_semester_key UNIQUE (school_year, semester);


--
-- TOC entry 4911 (class 2606 OID 16616)
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- TOC entry 4887 (class 2606 OID 16548)
-- Name: campuses campuses_campus_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campuses
    ADD CONSTRAINT campuses_campus_code_key UNIQUE (campus_code);


--
-- TOC entry 4889 (class 2606 OID 16546)
-- Name: campuses campuses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campuses
    ADD CONSTRAINT campuses_pkey PRIMARY KEY (id);


--
-- TOC entry 4918 (class 2606 OID 24994)
-- Name: class_schedules class_schedules_course_year_level_section_subject_weekday_s_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.class_schedules
    ADD CONSTRAINT class_schedules_course_year_level_section_subject_weekday_s_key UNIQUE (course, year_level, section, subject, weekday, start_time);


--
-- TOC entry 4920 (class 2606 OID 24992)
-- Name: class_schedules class_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.class_schedules
    ADD CONSTRAINT class_schedules_pkey PRIMARY KEY (id);


--
-- TOC entry 4925 (class 2606 OID 25040)
-- Name: class_schedules class_schedules_term_course_year_subject_time_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.class_schedules
    ADD CONSTRAINT class_schedules_term_course_year_subject_time_key UNIQUE (academic_term_id, course, year_level, section, subject, weekday, start_time);


--
-- TOC entry 4927 (class 2606 OID 25017)
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (course_code);


--
-- TOC entry 4916 (class 2606 OID 16642)
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- TOC entry 4892 (class 2606 OID 16555)
-- Name: parents parents_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.parents
    ADD CONSTRAINT parents_pkey PRIMARY KEY (id);


--
-- TOC entry 4894 (class 2606 OID 16557)
-- Name: parents parents_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.parents
    ADD CONSTRAINT parents_user_id_key UNIQUE (user_id);


--
-- TOC entry 4883 (class 2606 OID 16526)
-- Name: registration_requests registration_requests_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.registration_requests
    ADD CONSTRAINT registration_requests_email_key UNIQUE (email);


--
-- TOC entry 4885 (class 2606 OID 16524)
-- Name: registration_requests registration_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.registration_requests
    ADD CONSTRAINT registration_requests_pkey PRIMARY KEY (id);


--
-- TOC entry 4875 (class 2606 OID 16497)
-- Name: roles roles_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_name_key UNIQUE (name);


--
-- TOC entry 4877 (class 2606 OID 16495)
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- TOC entry 4905 (class 2606 OID 16587)
-- Name: students students_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_pkey PRIMARY KEY (id);


--
-- TOC entry 4907 (class 2606 OID 16591)
-- Name: students students_student_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_student_number_key UNIQUE (student_number);


--
-- TOC entry 4909 (class 2606 OID 16589)
-- Name: students students_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_user_id_key UNIQUE (user_id);


--
-- TOC entry 4897 (class 2606 OID 16573)
-- Name: teachers teachers_employee_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teachers
    ADD CONSTRAINT teachers_employee_number_key UNIQUE (employee_number);


--
-- TOC entry 4899 (class 2606 OID 16569)
-- Name: teachers teachers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teachers
    ADD CONSTRAINT teachers_pkey PRIMARY KEY (id);


--
-- TOC entry 4901 (class 2606 OID 16571)
-- Name: teachers teachers_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teachers
    ADD CONSTRAINT teachers_user_id_key UNIQUE (user_id);


--
-- TOC entry 4879 (class 2606 OID 16502)
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);


--
-- TOC entry 4871 (class 2606 OID 16488)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 4873 (class 2606 OID 16486)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 4928 (class 1259 OID 25032)
-- Name: academic_terms_one_current_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX academic_terms_one_current_idx ON public.academic_terms USING btree (is_current) WHERE is_current;


--
-- TOC entry 4912 (class 1259 OID 25007)
-- Name: attendance_user_schedule_date_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX attendance_user_schedule_date_idx ON public.attendance USING btree (user_id, class_schedule_id, attendance_date) WHERE (class_schedule_id IS NOT NULL);


--
-- TOC entry 4921 (class 1259 OID 25000)
-- Name: class_schedules_student_lookup_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX class_schedules_student_lookup_idx ON public.class_schedules USING btree (upper(course), upper(year_level), upper(section), weekday);


--
-- TOC entry 4922 (class 1259 OID 25001)
-- Name: class_schedules_teacher_lookup_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX class_schedules_teacher_lookup_idx ON public.class_schedules USING btree (teacher_user_id, weekday);


--
-- TOC entry 4923 (class 1259 OID 25041)
-- Name: class_schedules_term_active_lookup_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX class_schedules_term_active_lookup_idx ON public.class_schedules USING btree (academic_term_id, upper(course), upper(year_level), upper(section), weekday) WHERE (NOT is_archived);


--
-- TOC entry 4895 (class 1259 OID 16603)
-- Name: idx_employee_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_employee_number ON public.teachers USING btree (employee_number);


--
-- TOC entry 4913 (class 1259 OID 16649)
-- Name: idx_notifications_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_notifications_type ON public.notifications USING btree (type);


--
-- TOC entry 4914 (class 1259 OID 16648)
-- Name: idx_notifications_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_notifications_user ON public.notifications USING btree (user_id);


--
-- TOC entry 4890 (class 1259 OID 16604)
-- Name: idx_parent_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_parent_user ON public.parents USING btree (user_id);


--
-- TOC entry 4880 (class 1259 OID 16538)
-- Name: idx_registration_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_registration_email ON public.registration_requests USING btree (email);


--
-- TOC entry 4881 (class 1259 OID 16539)
-- Name: idx_registration_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_registration_status ON public.registration_requests USING btree (status);


--
-- TOC entry 4902 (class 1259 OID 16602)
-- Name: idx_student_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_student_number ON public.students USING btree (student_number);


--
-- TOC entry 4903 (class 1259 OID 16605)
-- Name: idx_student_parent; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_student_parent ON public.students USING btree (parent_id);


--
-- TOC entry 4869 (class 1259 OID 16537)
-- Name: idx_users_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_email ON public.users USING btree (email);


--
-- TOC entry 4941 (class 2606 OID 25002)
-- Name: attendance attendance_class_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_class_schedule_id_fkey FOREIGN KEY (class_schedule_id) REFERENCES public.class_schedules(id);


--
-- TOC entry 4945 (class 2606 OID 25033)
-- Name: class_schedules class_schedules_academic_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.class_schedules
    ADD CONSTRAINT class_schedules_academic_term_id_fkey FOREIGN KEY (academic_term_id) REFERENCES public.academic_terms(id);


--
-- TOC entry 4946 (class 2606 OID 24995)
-- Name: class_schedules class_schedules_teacher_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.class_schedules
    ADD CONSTRAINT class_schedules_teacher_user_id_fkey FOREIGN KEY (teacher_user_id) REFERENCES public.users(id);


--
-- TOC entry 4942 (class 2606 OID 16622)
-- Name: attendance fk_attendance_campus; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT fk_attendance_campus FOREIGN KEY (campus_id) REFERENCES public.campuses(id);


--
-- TOC entry 4943 (class 2606 OID 16617)
-- Name: attendance fk_attendance_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT fk_attendance_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4944 (class 2606 OID 16643)
-- Name: notifications fk_notifications_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4937 (class 2606 OID 16558)
-- Name: parents fk_parent_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.parents
    ADD CONSTRAINT fk_parent_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4935 (class 2606 OID 16532)
-- Name: registration_requests fk_registration_reviewer; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.registration_requests
    ADD CONSTRAINT fk_registration_reviewer FOREIGN KEY (reviewed_by) REFERENCES public.users(id);


--
-- TOC entry 4936 (class 2606 OID 16527)
-- Name: registration_requests fk_registration_role; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.registration_requests
    ADD CONSTRAINT fk_registration_role FOREIGN KEY (requested_role_id) REFERENCES public.roles(id);


--
-- TOC entry 4939 (class 2606 OID 16597)
-- Name: students fk_student_parent; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT fk_student_parent FOREIGN KEY (parent_id) REFERENCES public.parents(id) ON DELETE SET NULL;


--
-- TOC entry 4940 (class 2606 OID 16592)
-- Name: students fk_student_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT fk_student_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4938 (class 2606 OID 16574)
-- Name: teachers fk_teacher_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teachers
    ADD CONSTRAINT fk_teacher_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4933 (class 2606 OID 16508)
-- Name: user_roles fk_userroles_role; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT fk_userroles_role FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- TOC entry 4934 (class 2606 OID 16503)
-- Name: user_roles fk_userroles_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT fk_userroles_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


-- Completed on 2026-09-28 23:57:12

--
-- PostgreSQL database dump complete
--

