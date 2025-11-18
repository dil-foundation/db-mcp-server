#!/usr/bin/env python3
"""
Standalone test script to verify SQL validation fixes
"""

import re
from typing import Any, Dict


def _validate_sql_query(sql: str) -> Dict[str, Any]:
    """Validate SQL query for security (read-only) - FIXED VERSION"""
    sql_clean = sql.strip().upper()

    # Check for dangerous operations using word boundary matching
    dangerous_keywords = [
        'DROP', 'DELETE', 'INSERT', 'UPDATE', 'CREATE', 'ALTER',
        'TRUNCATE', 'GRANT', 'REVOKE', 'EXEC', 'EXECUTE'
    ]

    for keyword in dangerous_keywords:
        # Use word boundary matching to avoid false positives with column names
        # e.g., 'created_at' should not match 'CREATE'
        pattern = r'\b' + re.escape(keyword) + r'\b'
        if re.search(pattern, sql_clean):
            return {
                "is_valid": False,
                "error": f"Operation '{keyword}' is not allowed. Only SELECT queries are permitted."
            }

    # Check if it starts with SELECT or WITH (for CTEs)
    if not (sql_clean.startswith('SELECT') or sql_clean.startswith('WITH')):
        return {
            "is_valid": False,
            "error": "Only SELECT queries and CTEs (WITH) are allowed."
        }

    return {"is_valid": True}


def test_sql_validation():
    """Test the SQL validation with various queries"""

    print("=" * 80)
    print("Testing SQL Validation - Word Boundary Fix")
    print("=" * 80)
    print()

    # Test cases: (query, should_pass, description)
    test_cases = [
        # Should PASS - Valid queries with column names containing keywords
        ("SELECT id, created_at FROM users", True, "Query with 'created_at' column"),
        ("SELECT updated_at, deleted_at FROM applications", True, "Query with 'updated_at' and 'deleted_at'"),
        ("SELECT * FROM users WHERE created_at > NOW()", True, "WHERE clause with 'created_at'"),
        ("SELECT id, name, created_at, updated_at FROM profiles ORDER BY created_at", True, "Multiple timestamp columns"),
        ("SELECT user_id, truncated_name FROM data", True, "Column name 'truncated_name'"),
        ("SELECT insert_id, update_count FROM stats", True, "Columns 'insert_id' and 'update_count'"),
        ("SELECT executor_name, grant_date FROM permissions", True, "Columns with 'executor' and 'grant'"),

        # Should PASS - CTEs (Common Table Expressions)
        ("WITH cte AS (SELECT id FROM users) SELECT * FROM cte", True, "Simple CTE with SELECT"),
        ("""WITH ai_tutor_data AS (
            SELECT user_id, COUNT(*) as count
            FROM ai_tutor_user_exercise_progress
            WHERE updated_at >= CURRENT_DATE - INTERVAL '6 months'
            GROUP BY user_id
        )
        SELECT * FROM ai_tutor_data LIMIT 50""", True, "Complex CTE with aggregation"),
        ("WITH active_users AS (SELECT * FROM users WHERE status = 'active') SELECT COUNT(*) FROM active_users", True, "CTE with WHERE clause"),
        ("""WITH RECURSIVE org_chart AS (
            SELECT id, name, manager_id FROM employees WHERE manager_id IS NULL
            UNION ALL
            SELECT e.id, e.name, e.manager_id FROM employees e
            INNER JOIN org_chart oc ON e.manager_id = oc.id
        )
        SELECT * FROM org_chart""", True, "Recursive CTE"),
        ("with lowercase_cte as (select * from users) select * from lowercase_cte", True, "Lowercase CTE"),

        # Should FAIL - Actual dangerous operations
        ("CREATE TABLE test (id INT)", False, "CREATE TABLE statement"),
        ("DROP TABLE users", False, "DROP TABLE statement"),
        ("INSERT INTO users VALUES (1, 'test')", False, "INSERT statement"),
        ("UPDATE users SET name = 'test'", False, "UPDATE statement"),
        ("DELETE FROM users WHERE id = 1", False, "DELETE statement"),
        ("ALTER TABLE users ADD COLUMN test VARCHAR(50)", False, "ALTER TABLE statement"),
        ("TRUNCATE TABLE users", False, "TRUNCATE statement"),
        ("GRANT SELECT ON users TO public", False, "GRANT statement"),
        ("EXECUTE my_procedure()", False, "EXECUTE statement"),

        # Should FAIL - CTEs with dangerous operations
        ("WITH cte AS (INSERT INTO users VALUES (1, 'test')) SELECT * FROM cte", False, "CTE with INSERT"),
        ("WITH cte AS (UPDATE users SET name = 'test') SELECT * FROM cte", False, "CTE with UPDATE"),
        ("WITH cte AS (DELETE FROM users) SELECT * FROM cte", False, "CTE with DELETE"),

        # Edge cases
        ("SELECT * FROM users", True, "Simple SELECT *"),
        ("SELECT COUNT(*) FROM applications", True, "SELECT with COUNT"),
        ("select id, created_at from users", True, "Lowercase query with created_at"),
        ("  SELECT  created_at  FROM  users  ", True, "Query with extra whitespace"),
    ]

    passed = 0
    failed = 0

    for query, should_pass, description in test_cases:
        result = _validate_sql_query(query)
        is_valid = result.get("is_valid", False)

        # Check if the result matches expectation
        test_passed = (is_valid == should_pass)

        status = "[PASS]" if test_passed else "[FAIL]"
        expected = "PASS" if should_pass else "FAIL"
        actual = "PASS" if is_valid else "FAIL"

        print(f"{status} | {description}")
        print(f"     Query: {query}")
        print(f"     Expected: {expected}, Actual: {actual}")

        if not test_passed:
            print(f"     Error: {result.get('error', 'No error message')}")
            failed += 1
        else:
            passed += 1

        print()

    print("=" * 80)
    print(f"Test Results: {passed} passed, {failed} failed out of {len(test_cases)} total")
    print("=" * 80)

    if failed == 0:
        print("\n[SUCCESS] All tests passed! The word boundary fix is working correctly.")
        print("\nThe bug is FIXED:")
        print("  - Queries with 'created_at', 'updated_at', etc. now work correctly")
        print("  - Actual dangerous keywords like 'CREATE', 'UPDATE', etc. are still blocked")
        return 0
    else:
        print("\n[ERROR] Some tests failed. Please review the validation logic.")
        return 1


if __name__ == "__main__":
    import sys
    sys.exit(test_sql_validation())
