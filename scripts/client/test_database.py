import argparse
import getpass
import sys

import pymysql


def main():
    parser = argparse.ArgumentParser(
        description="Test database access through the load balancer."
    )
    parser.add_argument("host", help="NLB hostname")
    parser.add_argument(
        "--password-stdin",
        action="store_true",
        help="Read the password from stdin instead of prompting",
    )
    args = parser.parse_args()

    if args.password_stdin:
        password = sys.stdin.readline().removesuffix("\n")
    else:
        password = getpass.getpass("Password for lab2_client: ")

    if not password:
        print("FAIL: database password cannot be empty.", file=sys.stderr)
        return 1

    try:
        with pymysql.connect(
            host=args.host,
            port=3306,
            user="lab2_client",
            password=password,
            database="lab2_replication_test",
            connect_timeout=10,
            read_timeout=15,
            write_timeout=15,
        ) as connection:
            with connection.cursor() as cursor:
                cursor.execute("SET SESSION wsrep_sync_wait = 1")
                cursor.execute(
                    """
                    SELECT @@hostname, message
                    FROM checks
                    WHERE message = %s
                    LIMIT 1
                    """,
                    ("hello-from-lab2",),
                )
                row = cursor.fetchone()

        if row is None:
            print("FAIL: expected replication-test data was not found.")
            return 1

        print(f"PASS: connected through {args.host}")
        print(f"Database node: {row[0]}")
        print(f"Received: {row[1]}")
        return 0

    except pymysql.MySQLError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
