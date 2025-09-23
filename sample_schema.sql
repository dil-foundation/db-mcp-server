-- Mortgage Underwriting Database Schema
-- This schema supports a comprehensive mortgage underwriting system

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- CORE TABLES
-- =============================================================================

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    timezone VARCHAR(50) DEFAULT 'UTC',
    persona VARCHAR(50) NOT NULL CHECK (persona IN ('borrower', 'broker', 'underwriter', 'admin')),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Applications table
CREATE TABLE applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_number VARCHAR(50) UNIQUE NOT NULL,
    borrower_id UUID NOT NULL REFERENCES users(id),
    broker_id UUID REFERENCES users(id),
    underwriter_id UUID REFERENCES users(id),
    status VARCHAR(20) NOT NULL CHECK (status IN ('draft', 'submitted', 'processing', 'approved', 'declined', 'cancelled')),
    current_stage VARCHAR(50) NOT NULL,
    priority VARCHAR(20) DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    loan_amount DECIMAL(15,2) NOT NULL,
    property_value DECIMAL(15,2) NOT NULL,
    loan_to_value_ratio DECIMAL(5,4) GENERATED ALWAYS AS (loan_amount / property_value) STORED,
    -- Enhanced visibility and tracking fields
    visibility_status VARCHAR(20) DEFAULT 'visible' CHECK (visibility_status IN ('visible', 'hidden', 'archived')),
    is_active BOOLEAN DEFAULT TRUE,
    tags TEXT[] DEFAULT '{}',
    source VARCHAR(50) DEFAULT 'web' CHECK (source IN ('web', 'api', 'import', 'migration')),
    external_id VARCHAR(100), -- For integration with external systems
    -- Enhanced metadata for flexibility
    metadata JSONB DEFAULT '{}'::jsonb,
    custom_fields JSONB DEFAULT '{}'::jsonb, -- For dynamic application-specific fields
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    submitted_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_viewed_at TIMESTAMP WITH TIME ZONE,
    last_activity_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Documents table
CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    doc_type VARCHAR(50) NOT NULL,
    filename VARCHAR(255) NOT NULL,
    file_path VARCHAR(500),
    file_size BIGINT,
    mime_type VARCHAR(100),
    uploaded_by UUID NOT NULL REFERENCES users(id),
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    validation_status VARCHAR(20) DEFAULT 'pending' CHECK (validation_status IN ('pending', 'valid', 'invalid', 'needs_review')),
    validation_notes TEXT,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- =============================================================================
-- REFERENCE TABLES
-- =============================================================================

-- Roles table
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Permissions table
CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    resource VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Application stages table
CREATE TABLE application_stages (
    code VARCHAR(50) PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    description TEXT,
    order_index INTEGER NOT NULL,
    is_terminal BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Document types table
CREATE TABLE document_types (
    code VARCHAR(50) PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    description TEXT,
    required BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Application field definitions table (for dynamic fields)
CREATE TABLE application_field_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    field_name VARCHAR(100) UNIQUE NOT NULL,
    display_name VARCHAR(200) NOT NULL,
    field_type VARCHAR(50) NOT NULL CHECK (field_type IN ('text', 'number', 'date', 'boolean', 'select', 'multiselect', 'json')),
    description TEXT,
    is_required BOOLEAN DEFAULT FALSE,
    is_searchable BOOLEAN DEFAULT TRUE,
    is_filterable BOOLEAN DEFAULT TRUE,
    validation_rules JSONB DEFAULT '{}'::jsonb,
    options JSONB DEFAULT '[]'::jsonb, -- For select/multiselect fields
    default_value TEXT,
    category VARCHAR(100) DEFAULT 'general',
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Application field values table (for storing dynamic field values)
CREATE TABLE application_field_values (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    field_definition_id UUID NOT NULL REFERENCES application_field_definitions(id) ON DELETE CASCADE,
    field_value TEXT,
    json_value JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(application_id, field_definition_id)
);

-- Application visibility rules table
CREATE TABLE application_visibility_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_name VARCHAR(200) NOT NULL,
    description TEXT,
    user_persona VARCHAR(50) NOT NULL CHECK (user_persona IN ('borrower', 'broker', 'underwriter', 'admin')),
    visibility_conditions JSONB NOT NULL, -- JSON conditions for when this rule applies
    created_by UUID REFERENCES users(id),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Application access log table (for tracking who views what)
CREATE TABLE application_access_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    access_type VARCHAR(50) NOT NULL CHECK (access_type IN ('view', 'edit', 'download', 'print')),
    ip_address INET,
    user_agent TEXT,
    accessed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- RELATIONSHIP TABLES
-- =============================================================================

-- User roles junction table
CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    assigned_by UUID REFERENCES users(id),
    PRIMARY KEY (user_id, role_id)
);

-- Role permissions junction table
CREATE TABLE role_permissions (
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    granted_by UUID REFERENCES users(id),
    PRIMARY KEY (role_id, permission_id)
);

-- =============================================================================
-- AUDIT AND TRACKING TABLES
-- =============================================================================

-- Application timeline table
CREATE TABLE application_timeline (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    stage_code VARCHAR(50) NOT NULL REFERENCES application_stages(code),
    actor_user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    description TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Document validation history
CREATE TABLE document_validation_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    validator_user_id UUID NOT NULL REFERENCES users(id),
    previous_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,
    validation_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Users indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_persona ON users(persona);
CREATE INDEX idx_users_status ON users(status);

-- Applications indexes
CREATE INDEX idx_applications_borrower_id ON applications(borrower_id);
CREATE INDEX idx_applications_broker_id ON applications(broker_id);
CREATE INDEX idx_applications_underwriter_id ON applications(underwriter_id);
CREATE INDEX idx_applications_status ON applications(status);
CREATE INDEX idx_applications_current_stage ON applications(current_stage);
CREATE INDEX idx_applications_created_at ON applications(created_at);
CREATE INDEX idx_applications_application_number ON applications(application_number);
CREATE INDEX idx_applications_visibility_status ON applications(visibility_status);
CREATE INDEX idx_applications_is_active ON applications(is_active);
CREATE INDEX idx_applications_source ON applications(source);
CREATE INDEX idx_applications_external_id ON applications(external_id);
CREATE INDEX idx_applications_last_activity_at ON applications(last_activity_at);
CREATE INDEX idx_applications_tags ON applications USING GIN(tags);
CREATE INDEX idx_applications_metadata ON applications USING GIN(metadata);
CREATE INDEX idx_applications_custom_fields ON applications USING GIN(custom_fields);

-- Application field definitions indexes
CREATE INDEX idx_application_field_definitions_field_name ON application_field_definitions(field_name);
CREATE INDEX idx_application_field_definitions_category ON application_field_definitions(category);
CREATE INDEX idx_application_field_definitions_is_active ON application_field_definitions(is_active);
CREATE INDEX idx_application_field_definitions_is_searchable ON application_field_definitions(is_searchable);

-- Application field values indexes
CREATE INDEX idx_application_field_values_application_id ON application_field_values(application_id);
CREATE INDEX idx_application_field_values_field_definition_id ON application_field_values(field_definition_id);
CREATE INDEX idx_application_field_values_field_value ON application_field_values(field_value);

-- Application visibility rules indexes
CREATE INDEX idx_application_visibility_rules_user_persona ON application_visibility_rules(user_persona);
CREATE INDEX idx_application_visibility_rules_is_active ON application_visibility_rules(is_active);

-- Application access log indexes
CREATE INDEX idx_application_access_log_application_id ON application_access_log(application_id);
CREATE INDEX idx_application_access_log_user_id ON application_access_log(user_id);
CREATE INDEX idx_application_access_log_accessed_at ON application_access_log(accessed_at);
CREATE INDEX idx_application_access_log_access_type ON application_access_log(access_type);

-- Documents indexes
CREATE INDEX idx_documents_application_id ON documents(application_id);
CREATE INDEX idx_documents_doc_type ON documents(doc_type);
CREATE INDEX idx_documents_uploaded_by ON documents(uploaded_by);
CREATE INDEX idx_documents_validation_status ON documents(validation_status);
CREATE INDEX idx_documents_uploaded_at ON documents(uploaded_at);

-- Timeline indexes
CREATE INDEX idx_application_timeline_application_id ON application_timeline(application_id);
CREATE INDEX idx_application_timeline_created_at ON application_timeline(created_at);
CREATE INDEX idx_application_timeline_actor_user_id ON application_timeline(actor_user_id);

-- =============================================================================
-- VIEWS
-- =============================================================================

-- Application summary view
CREATE VIEW vw_application_summary AS
SELECT 
    a.id,
    a.application_number,
    a.status,
    a.current_stage,
    a.priority,
    a.loan_amount,
    a.property_value,
    a.loan_to_value_ratio,
    a.visibility_status,
    a.is_active,
    a.tags,
    a.source,
    a.external_id,
    a.created_at,
    a.submitted_at,
    a.last_viewed_at,
    a.last_activity_at,
    b.display_name as borrower_name,
    b.email as borrower_email,
    br.display_name as broker_name,
    u.display_name as underwriter_name,
    COUNT(d.id) as document_count,
    COUNT(CASE WHEN d.validation_status = 'valid' THEN 1 END) as valid_documents,
    COUNT(CASE WHEN d.validation_status = 'invalid' THEN 1 END) as invalid_documents
FROM applications a
LEFT JOIN users b ON a.borrower_id = b.id
LEFT JOIN users br ON a.broker_id = br.id
LEFT JOIN users u ON a.underwriter_id = u.id
LEFT JOIN documents d ON a.id = d.application_id
GROUP BY a.id, a.application_number, a.status, a.current_stage, a.priority, 
         a.loan_amount, a.property_value, a.loan_to_value_ratio, a.visibility_status,
         a.is_active, a.tags, a.source, a.external_id, a.created_at, 
         a.submitted_at, a.last_viewed_at, a.last_activity_at,
         b.display_name, b.email, br.display_name, u.display_name;

-- Document summary view
CREATE VIEW vw_document_summary AS
SELECT 
    d.id,
    d.application_id,
    a.application_number,
    d.doc_type,
    d.filename,
    d.validation_status,
    d.uploaded_at,
    u.display_name as uploaded_by_name,
    dt.display_name as document_type_name,
    dt.required
FROM documents d
JOIN applications a ON d.application_id = a.id
JOIN users u ON d.uploaded_by = u.id
LEFT JOIN document_types dt ON d.doc_type = dt.code;

-- User summary view
CREATE VIEW vw_user_summary AS
SELECT 
    u.id,
    u.email,
    u.display_name,
    u.persona,
    u.status,
    u.created_at,
    COUNT(DISTINCT a.id) as application_count,
    COUNT(DISTINCT CASE WHEN a.status = 'approved' THEN a.id END) as approved_applications,
    COUNT(DISTINCT d.id) as documents_uploaded
FROM users u
LEFT JOIN applications a ON u.id = a.borrower_id
LEFT JOIN documents d ON u.id = d.uploaded_by
GROUP BY u.id, u.email, u.display_name, u.persona, u.status, u.created_at;

-- Application timeline view
CREATE VIEW vw_application_timeline AS
SELECT 
    at.id,
    at.application_id,
    a.application_number,
    at.stage_code,
    ast.display_name as stage_name,
    at.action,
    at.description,
    at.actor_user_id,
    u.display_name as actor_name,
    at.created_at,
    at.metadata
FROM application_timeline at
JOIN applications a ON at.application_id = a.id
LEFT JOIN application_stages ast ON at.stage_code = ast.code
LEFT JOIN users u ON at.actor_user_id = u.id
ORDER BY at.created_at DESC;

-- Application search view (for flexible searching)
CREATE VIEW vw_application_search AS
SELECT 
    a.id,
    a.application_number,
    a.status,
    a.current_stage,
    a.priority,
    a.loan_amount,
    a.property_value,
    a.visibility_status,
    a.is_active,
    a.tags,
    a.source,
    a.external_id,
    a.created_at,
    a.submitted_at,
    a.last_activity_at,
    b.display_name as borrower_name,
    b.email as borrower_email,
    br.display_name as broker_name,
    u.display_name as underwriter_name,
    a.metadata,
    a.custom_fields,
    -- Searchable text field combining multiple fields
    CONCAT_WS(' ', 
        a.application_number,
        b.display_name,
        b.email,
        br.display_name,
        u.display_name,
        a.external_id,
        array_to_string(a.tags, ' ')
    ) as searchable_text
FROM applications a
LEFT JOIN users b ON a.borrower_id = b.id
LEFT JOIN users br ON a.broker_id = br.id
LEFT JOIN users u ON a.underwriter_id = u.id;

-- Application field values view (for dynamic fields)
CREATE VIEW vw_application_field_values AS
SELECT 
    afv.id,
    afv.application_id,
    a.application_number,
    afd.field_name,
    afd.display_name as field_display_name,
    afd.field_type,
    afd.category,
    afv.field_value,
    afv.json_value,
    afv.created_at,
    afv.updated_at
FROM application_field_values afv
JOIN applications a ON afv.application_id = a.id
JOIN application_field_definitions afd ON afv.field_definition_id = afd.id
WHERE afd.is_active = TRUE;

-- Application access summary view
CREATE VIEW vw_application_access_summary AS
SELECT 
    a.id as application_id,
    a.application_number,
    COUNT(aal.id) as total_accesses,
    COUNT(DISTINCT aal.user_id) as unique_viewers,
    MAX(aal.accessed_at) as last_accessed_at,
    COUNT(CASE WHEN aal.access_type = 'view' THEN 1 END) as view_count,
    COUNT(CASE WHEN aal.access_type = 'edit' THEN 1 END) as edit_count,
    COUNT(CASE WHEN aal.access_type = 'download' THEN 1 END) as download_count
FROM applications a
LEFT JOIN application_access_log aal ON a.id = aal.application_id
GROUP BY a.id, a.application_number;

-- =============================================================================
-- FUNCTIONS
-- =============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_applications_updated_at BEFORE UPDATE ON applications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Trigger to update last_activity_at when applications are modified
CREATE TRIGGER update_applications_activity BEFORE UPDATE ON applications
    FOR EACH ROW EXECUTE FUNCTION update_application_activity();

-- Trigger to update field definitions updated_at
CREATE TRIGGER update_application_field_definitions_updated_at BEFORE UPDATE ON application_field_definitions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Trigger to update field values updated_at
CREATE TRIGGER update_application_field_values_updated_at BEFORE UPDATE ON application_field_values
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Trigger to update visibility rules updated_at
CREATE TRIGGER update_application_visibility_rules_updated_at BEFORE UPDATE ON application_visibility_rules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to generate application number
CREATE OR REPLACE FUNCTION generate_application_number()
RETURNS TEXT AS $$
DECLARE
    year_part TEXT;
    sequence_num INTEGER;
    app_number TEXT;
BEGIN
    year_part := EXTRACT(YEAR FROM CURRENT_DATE)::TEXT;
    
    SELECT COALESCE(MAX(CAST(SUBSTRING(application_number FROM 'APP-' || year_part || '-(.+)') AS INTEGER)), 0) + 1
    INTO sequence_num
    FROM applications
    WHERE application_number LIKE 'APP-' || year_part || '-%';
    
    app_number := 'APP-' || year_part || '-' || LPAD(sequence_num::TEXT, 3, '0');
    
    RETURN app_number;
END;
$$ LANGUAGE plpgsql;

-- Function to update application last_activity_at
CREATE OR REPLACE FUNCTION update_application_activity()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_activity_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to log application access
CREATE OR REPLACE FUNCTION log_application_access(
    p_application_id UUID,
    p_user_id UUID,
    p_access_type VARCHAR(50),
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO application_access_log (
        application_id, user_id, access_type, ip_address, user_agent
    ) VALUES (
        p_application_id, p_user_id, p_access_type, p_ip_address, p_user_agent
    );
    
    -- Update last_viewed_at for view access
    IF p_access_type = 'view' THEN
        UPDATE applications 
        SET last_viewed_at = CURRENT_TIMESTAMP 
        WHERE id = p_application_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to get applications visible to a user
CREATE OR REPLACE FUNCTION get_visible_applications(p_user_id UUID)
RETURNS TABLE (
    application_id UUID,
    application_number VARCHAR(50),
    status VARCHAR(20),
    current_stage VARCHAR(50),
    priority VARCHAR(20),
    loan_amount DECIMAL(15,2),
    property_value DECIMAL(15,2),
    visibility_status VARCHAR(20),
    is_active BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        a.application_number,
        a.status,
        a.current_stage,
        a.priority,
        a.loan_amount,
        a.property_value,
        a.visibility_status,
        a.is_active,
        a.created_at
    FROM applications a
    JOIN users u ON u.id = p_user_id
    WHERE 
        a.visibility_status = 'visible' 
        AND a.is_active = TRUE
        AND (
            -- Borrower can see their own applications
            (u.persona = 'borrower' AND a.borrower_id = p_user_id)
            OR
            -- Broker can see applications they're assigned to
            (u.persona = 'broker' AND a.broker_id = p_user_id)
            OR
            -- Underwriter can see applications they're assigned to
            (u.persona = 'underwriter' AND a.underwriter_id = p_user_id)
            OR
            -- Admin can see all applications
            (u.persona = 'admin')
        );
END;
$$ LANGUAGE plpgsql;

-- Function to search applications with flexible criteria
CREATE OR REPLACE FUNCTION search_applications(
    p_search_text TEXT DEFAULT NULL,
    p_status VARCHAR(20) DEFAULT NULL,
    p_priority VARCHAR(20) DEFAULT NULL,
    p_visibility_status VARCHAR(20) DEFAULT NULL,
    p_tags TEXT[] DEFAULT NULL,
    p_source VARCHAR(50) DEFAULT NULL,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    application_id UUID,
    application_number VARCHAR(50),
    status VARCHAR(20),
    current_stage VARCHAR(50),
    priority VARCHAR(20),
    loan_amount DECIMAL(15,2),
    property_value DECIMAL(15,2),
    borrower_name VARCHAR(255),
    broker_name VARCHAR(255),
    underwriter_name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE,
    last_activity_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        a.application_number,
        a.status,
        a.current_stage,
        a.priority,
        a.loan_amount,
        a.property_value,
        b.display_name,
        br.display_name,
        u.display_name,
        a.created_at,
        a.last_activity_at
    FROM applications a
    LEFT JOIN users b ON a.borrower_id = b.id
    LEFT JOIN users br ON a.broker_id = br.id
    LEFT JOIN users u ON a.underwriter_id = u.id
    WHERE 
        (p_search_text IS NULL OR 
         CONCAT_WS(' ', a.application_number, b.display_name, br.display_name, u.display_name, a.external_id) ILIKE '%' || p_search_text || '%')
        AND (p_status IS NULL OR a.status = p_status)
        AND (p_priority IS NULL OR a.priority = p_priority)
        AND (p_visibility_status IS NULL OR a.visibility_status = p_visibility_status)
        AND (p_tags IS NULL OR a.tags && p_tags)
        AND (p_source IS NULL OR a.source = p_source)
        AND a.is_active = TRUE
    ORDER BY a.last_activity_at DESC NULLS LAST, a.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- INITIAL DATA
-- =============================================================================

-- Insert application stages
INSERT INTO application_stages (code, display_name, description, order_index, is_terminal) VALUES
('submitted', 'Application Submitted', 'Initial application received', 1, FALSE),
('file_validation', 'File Validation', 'Validating uploaded documents', 2, FALSE),
('data_extraction', 'Data Extraction', 'Extracting data from documents', 3, FALSE),
('data_validation', 'Data Validation', 'Validating extracted data', 4, FALSE),
('underwriter_assigned', 'Underwriter Assigned', 'Application assigned to underwriter', 5, FALSE),
('under_review', 'Under Review', 'Underwriter reviewing application', 6, FALSE),
('decision_pending', 'Decision Pending', 'Awaiting final decision', 7, FALSE),
('approved', 'Approved', 'Application approved', 8, TRUE),
('declined', 'Declined', 'Application declined', 9, TRUE),
('cancelled', 'Cancelled', 'Application cancelled', 10, TRUE);

-- Insert document types
INSERT INTO document_types (code, display_name, description, required) VALUES
('pay_stub', 'Pay Stub', 'Recent pay stub showing income', TRUE),
('bank_statement', 'Bank Statement', 'Recent bank statements', TRUE),
('tax_return', 'Tax Return', 'Previous year tax returns', TRUE),
('credit_report', 'Credit Report', 'Credit report from bureau', TRUE),
('property_appraisal', 'Property Appraisal', 'Property valuation report', TRUE),
('insurance_policy', 'Insurance Policy', 'Homeowners insurance policy', TRUE),
('employment_verification', 'Employment Verification', 'Employment verification letter', FALSE),
('asset_documentation', 'Asset Documentation', 'Investment or asset statements', FALSE);

-- Insert roles
INSERT INTO roles (id, name, description) VALUES
('b0000000-0000-0000-0000-000000000001', 'borrower', 'Mortgage applicant'),
('b0000000-0000-0000-0000-000000000002', 'broker', 'Mortgage broker'),
('b0000000-0000-0000-0000-000000000003', 'underwriter', 'Underwriting professional'),
('b0000000-0000-0000-0000-000000000004', 'admin', 'System administrator'),
('b0000000-0000-0000-0000-000000000005', 'supervisor', 'Underwriting supervisor');

-- Insert permissions
INSERT INTO permissions (id, name, description, resource, action) VALUES
('c0000000-0000-0000-0000-000000000001', 'view_own_applications', 'View own applications', 'applications', 'read'),
('c0000000-0000-0000-0000-000000000002', 'view_assigned_applications', 'View assigned applications', 'applications', 'read'),
('c0000000-0000-0000-0000-000000000003', 'update_application_status', 'Update application status', 'applications', 'update'),
('c0000000-0000-0000-0000-000000000004', 'validate_documents', 'Validate documents', 'documents', 'update'),
('c0000000-0000-0000-0000-000000000005', 'make_decisions', 'Make underwriting decisions', 'decisions', 'create'),
('c0000000-0000-0000-0000-000000000006', 'manage_users', 'Manage user accounts', 'users', 'create'),
('c0000000-0000-0000-0000-000000000007', 'view_analytics', 'View system analytics', 'analytics', 'read'),
('c0000000-0000-0000-0000-000000000008', 'upload_documents', 'Upload application documents', 'documents', 'create'),
('c0000000-0000-0000-0000-000000000009', 'assign_underwriters', 'Assign applications to underwriters', 'assignments', 'create'),
('c0000000-0000-0000-0000-000000000010', 'manage_application_fields', 'Manage dynamic application fields', 'application_fields', 'create'),
('c0000000-0000-0000-0000-000000000011', 'search_applications', 'Search applications with flexible criteria', 'applications', 'read'),
('c0000000-0000-0000-0000-000000000012', 'view_application_analytics', 'View application access analytics', 'analytics', 'read');

-- Insert sample application field definitions
INSERT INTO application_field_definitions (field_name, display_name, field_type, description, is_required, category, sort_order) VALUES
('property_address', 'Property Address', 'text', 'Full address of the property being purchased', TRUE, 'property', 1),
('property_type', 'Property Type', 'select', 'Type of property', TRUE, 'property', 2),
('occupancy_type', 'Occupancy Type', 'select', 'How the property will be occupied', TRUE, 'property', 3),
('credit_score', 'Credit Score', 'number', 'Applicant credit score', TRUE, 'financial', 4),
('debt_to_income_ratio', 'Debt-to-Income Ratio', 'number', 'Monthly debt payments divided by monthly income', TRUE, 'financial', 5),
('employment_years', 'Years of Employment', 'number', 'Years at current job', FALSE, 'employment', 6),
('down_payment_source', 'Down Payment Source', 'select', 'Source of down payment funds', FALSE, 'financial', 7),
('special_conditions', 'Special Conditions', 'text', 'Any special conditions or notes', FALSE, 'general', 8),
('referral_source', 'Referral Source', 'select', 'How the applicant was referred', FALSE, 'general', 9);

-- Insert options for select fields
UPDATE application_field_definitions 
SET options = '["Single Family", "Condo", "Townhouse", "Multi-Family", "Commercial"]'::jsonb
WHERE field_name = 'property_type';

UPDATE application_field_definitions 
SET options = '["Primary Residence", "Secondary Home", "Investment Property"]'::jsonb
WHERE field_name = 'occupancy_type';

UPDATE application_field_definitions 
SET options = '["Savings", "Gift", "Sale of Property", "Retirement Funds", "Other"]'::jsonb
WHERE field_name = 'down_payment_source';

UPDATE application_field_definitions 
SET options = '["Website", "Referral", "Advertisement", "Social Media", "Direct Mail", "Other"]'::jsonb
WHERE field_name = 'referral_source';

-- Insert sample visibility rules
INSERT INTO application_visibility_rules (rule_name, description, user_persona, visibility_conditions, created_by) VALUES
('borrower_own_applications', 'Borrowers can only see their own applications', 'borrower', '{"condition": "borrower_id", "operator": "equals", "value": "user_id"}'::jsonb, '550e8400-e29b-41d4-a716-446655440015'),
('broker_assigned_applications', 'Brokers can see applications they are assigned to', 'broker', '{"condition": "broker_id", "operator": "equals", "value": "user_id"}'::jsonb, '550e8400-e29b-41d4-a716-446655440015'),
('underwriter_assigned_applications', 'Underwriters can see applications they are assigned to', 'underwriter', '{"condition": "underwriter_id", "operator": "equals", "value": "user_id"}'::jsonb, '550e8400-e29b-41d4-a716-446655440015'),
('admin_all_applications', 'Admins can see all applications', 'admin', '{"condition": "always", "operator": "true"}'::jsonb, '550e8400-e29b-41d4-a716-446655440015');

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE users IS 'System users including borrowers, brokers, underwriters, and administrators';
COMMENT ON TABLE applications IS 'Mortgage applications with enhanced visibility, tracking, and flexible schema support';
COMMENT ON TABLE documents IS 'Application documents with validation status and metadata';
COMMENT ON TABLE application_stages IS 'Defines the workflow stages for mortgage applications';
COMMENT ON TABLE document_types IS 'Defines the types of documents required for applications';
COMMENT ON TABLE application_timeline IS 'Audit trail of application status changes and actions';
COMMENT ON TABLE document_validation_history IS 'History of document validation status changes';
COMMENT ON TABLE application_field_definitions IS 'Dynamic field definitions for flexible application schema';
COMMENT ON TABLE application_field_values IS 'Values for dynamic application fields';
COMMENT ON TABLE application_visibility_rules IS 'Rules controlling application visibility based on user persona';
COMMENT ON TABLE application_access_log IS 'Audit log of application access for analytics and security';

COMMENT ON COLUMN applications.loan_to_value_ratio IS 'Calculated field: loan_amount / property_value';
COMMENT ON COLUMN applications.visibility_status IS 'Controls application visibility: visible, hidden, or archived';
COMMENT ON COLUMN applications.is_active IS 'Soft delete flag for applications';
COMMENT ON COLUMN applications.tags IS 'Array of tags for categorization and filtering';
COMMENT ON COLUMN applications.source IS 'Source of application creation (web, api, import, migration)';
COMMENT ON COLUMN applications.external_id IS 'External system identifier for integration';
COMMENT ON COLUMN applications.metadata IS 'JSON field for storing additional application-specific data';
COMMENT ON COLUMN applications.custom_fields IS 'JSON field for storing dynamic application-specific fields';
COMMENT ON COLUMN applications.last_viewed_at IS 'Timestamp of last view access';
COMMENT ON COLUMN applications.last_activity_at IS 'Timestamp of last activity/update';
COMMENT ON COLUMN documents.metadata IS 'JSON field for storing document-specific metadata';
COMMENT ON COLUMN application_timeline.metadata IS 'JSON field for storing timeline event-specific data';
COMMENT ON COLUMN application_field_definitions.validation_rules IS 'JSON validation rules for field values';
COMMENT ON COLUMN application_field_definitions.options IS 'JSON array of options for select/multiselect fields';
COMMENT ON COLUMN application_field_values.json_value IS 'JSON value for complex field types';
COMMENT ON COLUMN application_visibility_rules.visibility_conditions IS 'JSON conditions for when visibility rules apply';
