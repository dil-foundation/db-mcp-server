#!/usr/bin/env python3
"""
Test script to verify SQL validation fixes
"""

import sys
import os

# Add the current directory to path to import mcp_server
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mcp_server import DatabaseMCP


def test_sql_validation():
    """Test the SQL validation with various queries"""

    # Create a DatabaseMCP instance (no need for actual DB connection for validation testing)
    db_mcp = DatabaseMCP(user_identity="test_user")

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

        # Should FAIL - Actual dangerous operations
        ("CREATE TABLE test (id INT)", False, "CREATE TABLE statement"),
        ("DROP TABLE users", False, "DROP TABLE statement"),
        ("INSERT INTO users VALUES (1, 'test')", False, "INSERT statement"),
        ("UPDATE users SET name = 'test'", False, "UPDATE statement"),
        ("DELETE FROM users WHERE id = 1", False, "DELETE statement"),
        ("ALTER TABLE users ADD COLUMN test VARCHAR(50)", False, "ALTER TABLE statement"),
        ("TRUNCATE TABLE users", False, "TRUNCATE statement"),
        ("GRANT SELECT ON users TO public", False, "GRANT statement"),

        # Edge cases
        ("SELECT * FROM users", True, "Simple SELECT *"),
        ("SELECT COUNT(*) FROM applications", True, "SELECT with COUNT"),
        ("select id, created_at from users", True, "Lowercase query with created_at"),
    ]

    passed = 0
    failed = 0

    for query, should_pass, description in test_cases:
        result = db_mcp._validate_sql_query(query)
        is_valid = result.get("is_valid", False)

        # Check if the result matches expectation
        test_passed = (is_valid == should_pass)

        status = "✓ PASS" if test_passed else "✗ FAIL"
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
        print("✓ All tests passed! The word boundary fix is working correctly.")
        return 0
    else:
        print("✗ Some tests failed. Please review the validation logic.")
        return 1


if __name__ == "__main__":
    sys.exit(test_sql_validation())
