using GenerateData.Models;
using Microsoft.EntityFrameworkCore;

namespace GenerateData.Data;

public partial class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options)
        : base(options)
    {
    }

    public virtual DbSet<Counterparty> Counterparties { get; set; }

    public virtual DbSet<CounterpartyRole> CounterpartyRoles { get; set; }

    public virtual DbSet<Invoice> Invoices { get; set; }

    public virtual DbSet<ListEntry> ListEntries { get; set; }

    public virtual DbSet<Product> Products { get; set; }

    public virtual DbSet<ProductUnit> ProductUnits { get; set; }

    public virtual DbSet<Storage> Storages { get; set; }

    public virtual DbSet<StorageKeeper> StorageKeepers { get; set; }

    public virtual DbSet<StorageProduct> StorageProducts { get; set; }

    public virtual DbSet<User> Users { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder
            .HasPostgresEnum("invoice_type", new[] { "supply", "transfer", "release" })
            .HasPostgresEnum("user_role", new[] { "owner", "manager", "storage_keeper" })
            .HasPostgresEnum("invoice_status", new[] { "draft", "processing", "processed", "cancelled" });

        modelBuilder.Entity<Counterparty>(entity =>
        {
            entity.HasKey(e => e.Name).HasName("provider_pkey");

            entity.ToTable("counterparty");

            entity.HasIndex(e => e.Email, "unique_counterparty_email").IsUnique();

            entity.HasIndex(e => e.PhoneNumber, "unique_counterparty_phone_number").IsUnique();

            entity.Property(e => e.Name)
                .HasMaxLength(100)
                .HasColumnName("name");
            entity.Property(e => e.Email)
                .HasMaxLength(255)
                .HasColumnName("email");
            entity.Property(e => e.PhoneNumber)
                .HasMaxLength(13)
                .HasColumnName("phone_number");

            entity.HasMany(d => d.Roles).WithMany(p => p.CounterpartyNames)
                .UsingEntity<Dictionary<string, object>>(
                    "CounterpartyRoleMap",
                    r => r.HasOne<CounterpartyRole>().WithMany()
                        .HasForeignKey("RoleId")
                        .HasConstraintName("counterparty_role_map_role_id_fkey"),
                    l => l.HasOne<Counterparty>().WithMany()
                        .HasForeignKey("CounterpartyName")
                        .HasConstraintName("counterparty_role_map_counterparty_name_fkey"),
                    j =>
                    {
                        j.HasKey("CounterpartyName", "RoleId").HasName("counterparty_role_map_pkey");
                        j.ToTable("counterparty_role_map");
                        j.IndexerProperty<string>("CounterpartyName")
                            .HasMaxLength(100)
                            .HasColumnName("counterparty_name");
                        j.IndexerProperty<int>("RoleId").HasColumnName("role_id");
                    });
        });

        modelBuilder.Entity<CounterpartyRole>(entity =>
        {
            entity.HasKey(e => e.RoleId).HasName("counterparty_role_pkey");

            entity.ToTable("counterparty_role");

            entity.HasIndex(e => e.Name, "counterparty_role_name_key").IsUnique();

            entity.Property(e => e.RoleId).HasColumnName("role_id");
            entity.Property(e => e.Name)
                .HasMaxLength(50)
                .HasColumnName("name");
        });

        modelBuilder.Entity<Invoice>(entity =>
        {
            entity.HasKey(e => e.InvoiceId).HasName("invoice_pkey");

            entity.ToTable("invoice");

            entity.Property(e => e.InvoiceId).HasColumnName("invoice_id");
            entity.Property(e => e.CounterpartyName)
                .HasMaxLength(100)
                .HasColumnName("counterparty_name");
            entity.Property(e => e.Date)
                .HasDefaultValueSql("CURRENT_DATE")
                .HasColumnName("date");
            entity.Property(e => e.ReceiverKeeperPhone)
                .HasMaxLength(13)
                .HasColumnName("receiver_keeper_phone");
            entity.Property(e => e.ReceiverStorageName)
                .HasMaxLength(100)
                .HasColumnName("receiver_storage_name");
            entity.Property(e => e.SenderKeeperPhone)
                .HasMaxLength(13)
                .HasColumnName("sender_keeper_phone");
            entity.Property(e => e.SenderStorageName)
                .HasMaxLength(100)
                .HasColumnName("sender_storage_name");
            entity.Property(e => e.Type)
                .HasColumnName("type")
                .HasColumnType("invoice_type");
            entity.Property(e => e.Status)
                          .HasColumnType("invoice_status") 
                          .HasDefaultValue(InvoiceStatus.draft)
                          .IsRequired();

            entity.HasOne(d => d.CounterpartyNameNavigation).WithMany(p => p.Invoices)
                .HasForeignKey(d => d.CounterpartyName)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("invoice_counterparty_name_fkey");

            entity.HasOne(d => d.ReceiverKeeperPhoneNavigation).WithMany(p => p.InvoiceReceiverKeeperPhoneNavigations)
                .HasForeignKey(d => d.ReceiverKeeperPhone)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("invoice_receiver_keeper_phone_fkey");

            entity.HasOne(d => d.ReceiverStorageNameNavigation).WithMany(p => p.InvoiceReceiverStorageNameNavigations)
                .HasForeignKey(d => d.ReceiverStorageName)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("invoice_receiver_storage_name_fkey");

            entity.HasOne(d => d.SenderKeeperPhoneNavigation).WithMany(p => p.InvoiceSenderKeeperPhoneNavigations)
                .HasForeignKey(d => d.SenderKeeperPhone)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("invoice_sender_keeper_phone_fkey");

            entity.HasOne(d => d.SenderStorageNameNavigation).WithMany(p => p.InvoiceSenderStorageNameNavigations)
                .HasForeignKey(d => d.SenderStorageName)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("invoice_sender_storage_name_fkey");
        });

        modelBuilder.Entity<ListEntry>(entity =>
        {
            entity.HasKey(e => new { e.ProductName, e.InvoiceId }).HasName("list_entry_pkey");

            entity.ToTable("list_entry");

            entity.Property(e => e.ProductName)
                .HasMaxLength(100)
                .HasColumnName("product_name");
            entity.Property(e => e.InvoiceId).HasColumnName("invoice_id");
            entity.Property(e => e.Count)
                .HasPrecision(10, 2)
                .HasColumnName("count");
            entity.Property(e => e.Price)
                .HasPrecision(10, 2)
                .HasColumnName("price");

            entity.HasOne(d => d.Invoice).WithMany(p => p.ListEntries)
                .HasForeignKey(d => d.InvoiceId)
                .HasConstraintName("list_entry_invoice_id_fkey");

            entity.HasOne(d => d.ProductNameNavigation).WithMany(p => p.ListEntries)
                .HasForeignKey(d => d.ProductName)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("list_entry_product_name_fkey");
        });

        modelBuilder.Entity<Product>(entity =>
        {
            entity.HasKey(e => e.ProductName).HasName("product_pkey");

            entity.ToTable("product");

            entity.HasIndex(e => e.ProductName, "unique_product_name").IsUnique();

            entity.Property(e => e.ProductName)
                .HasMaxLength(100)
                .HasColumnName("product_name");
            entity.Property(e => e.LastPrice)
                .HasPrecision(10, 2)
                .HasColumnName("last_price");
            entity.Property(e => e.UnitCode)
                .HasMaxLength(10)
                .HasColumnName("unit_code");

            entity.HasOne(d => d.UnitCodeNavigation).WithMany(p => p.Products)
                .HasForeignKey(d => d.UnitCode)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("product_unit_code_fkey");
        });

        modelBuilder.Entity<ProductUnit>(entity =>
        {
            entity.HasKey(e => e.UnitCode).HasName("product_units_pkey");

            entity.ToTable("product_units");

            entity.HasIndex(e => e.UnitName, "unique_product_unit_name").IsUnique();

            entity.Property(e => e.UnitCode)
                .HasMaxLength(10)
                .HasColumnName("unit_code");
            entity.Property(e => e.UnitName)
                .HasMaxLength(50)
                .HasColumnName("unit_name");
        });

        modelBuilder.Entity<Storage>(entity =>
        {
            entity.HasKey(e => e.Name).HasName("storage_pkey");

            entity.ToTable("storage");

            entity.Property(e => e.Name)
                .HasMaxLength(100)
                .HasColumnName("name");
            entity.Property(e => e.City)
                .HasMaxLength(50)
                .HasColumnName("city");
            entity.Property(e => e.HouseNumber)
                .HasMaxLength(3)
                .HasColumnName("house_number");
            entity.Property(e => e.PostalCode)
                .HasMaxLength(8)
                .HasColumnName("postal_code");
            entity.Property(e => e.Region)
                .HasMaxLength(30)
                .HasColumnName("region");
            entity.Property(e => e.StreetName)
                .HasMaxLength(100)
                .HasColumnName("street_name");
        });

        modelBuilder.Entity<StorageKeeper>(entity =>
        {
            entity.HasKey(e => e.PhoneNumber).HasName("storage_keeper_pkey");

            entity.ToTable("storage_keeper");

            entity.HasIndex(e => e.Email, "unique_storage_keeper_email").IsUnique();

            entity.HasIndex(e => e.UserId, "unique_user_per_keeper").IsUnique();

            entity.Property(e => e.PhoneNumber)
                .HasMaxLength(13)
                .HasColumnName("phone_number");
            entity.Property(e => e.Email)
                .HasMaxLength(255)
                .HasColumnName("email");
            entity.Property(e => e.FirstName)
                .HasMaxLength(50)
                .HasColumnName("first_name");
            entity.Property(e => e.LastName)
                .HasMaxLength(50)
                .HasColumnName("last_name");
            entity.Property(e => e.StorageName)
                .HasMaxLength(100)
                .HasColumnName("storage_name");
            entity.Property(e => e.UserId).HasColumnName("user_id");

            entity.HasOne(d => d.StorageNameNavigation).WithMany(p => p.StorageKeepers)
                .HasForeignKey(d => d.StorageName)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("storage_keeper_storage_name_fkey");

            entity.HasOne(d => d.User).WithOne(p => p.StorageKeeper)
                .HasForeignKey<StorageKeeper>(d => d.UserId)
                .OnDelete(DeleteBehavior.SetNull)
                .HasConstraintName("fk_storage_keeper_user");
        });

        modelBuilder.Entity<StorageProduct>(entity =>
        {
            entity.HasKey(e => new { e.ProductName, e.StorageName }).HasName("storage_product_pkey");

            entity.ToTable("storage_product");

            entity.Property(e => e.ProductName)
                .HasMaxLength(100)
                .HasColumnName("product_name");
            entity.Property(e => e.StorageName)
                .HasMaxLength(100)
                .HasColumnName("storage_name");
            entity.Property(e => e.Count)
                .HasPrecision(10, 2)
                .HasColumnName("count");
            entity.Property(e => e.MinimalCount)
                .HasPrecision(10, 2)
                .HasColumnName("minimal_count");

            entity.HasOne(d => d.ProductNameNavigation).WithMany(p => p.StorageProducts)
                .HasForeignKey(d => d.ProductName)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("storage_product_product_name_fkey");

            entity.HasOne(d => d.StorageNameNavigation).WithMany(p => p.StorageProducts)
                .HasForeignKey(d => d.StorageName)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("storage_product_storage_name_fkey");
        });

        modelBuilder.Entity<User>(entity =>
        {
            entity.HasKey(e => e.UserId).HasName("user_pkey");

            entity.ToTable("user");

            entity.HasIndex(e => e.Username, "user_username_key").IsUnique();

            entity.Property(e => e.UserId).HasColumnName("user_id");
            entity.Property(e => e.PasswordHash)
                .HasMaxLength(255)
                .HasColumnName("password_hash");
            entity.Property(e => e.Username)
                .HasMaxLength(101)
                .HasColumnName("username");
            entity.Property(e => e.Role)
                .HasColumnName("role")
                .HasColumnType("user_role");
        });

        OnModelCreatingPartial(modelBuilder);
    }

    partial void OnModelCreatingPartial(ModelBuilder modelBuilder);
}
