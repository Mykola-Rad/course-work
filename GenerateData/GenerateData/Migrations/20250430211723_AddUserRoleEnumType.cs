using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace GenerateData.Migrations
{
    /// <inheritdoc />
    public partial class AddUserRoleEnumType : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "role",
                table: "user",
                type: "user_role",
                nullable: false);

            migrationBuilder.AlterColumn<string>(
               name: "type",
               table: "invoice",
               type: "invoice_type",
               nullable: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<int>(
                name: "role",
                table: "user",
                type: "integer", 
                nullable: false);

            migrationBuilder.AlterColumn<int>(
               name: "type",
               table: "invoice",
               type: "integer",
               nullable: false);
        }
    }
}
