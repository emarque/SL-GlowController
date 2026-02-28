using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.ComponentModel.DataAnnotations;
using System.Text.RegularExpressions;

namespace GlowPersistenceAPI.Controllers;

/// <summary>
/// Entity Framework database context for glow persistence storage.
/// </summary>
public class GlowDbContext : DbContext
{
    public GlowDbContext(DbContextOptions<GlowDbContext> options) : base(options) { }

    public DbSet<GlowRecord> GlowRecords => Set<GlowRecord>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<GlowRecord>(entity =>
        {
            entity.HasKey(e => e.ObjectId);
            entity.Property(e => e.ObjectId).HasMaxLength(36).IsRequired();
            entity.Property(e => e.Data).IsRequired();
            entity.Property(e => e.UpdatedAt).IsRequired();
        });
    }
}

/// <summary>
/// Represents a stored glow data record for a Second Life object.
/// </summary>
public class GlowRecord
{
    [Key]
    [MaxLength(36)]
    public string ObjectId { get; set; } = string.Empty;

    /// <summary>
    /// Pipe-delimited glow data in format "faceCounts;glowValues"
    /// e.g. "4|6|8;0.5|0.3|0.0|..."
    /// </summary>
    public string Data { get; set; } = string.Empty;

    public DateTime UpdatedAt { get; set; }
}

/// <summary>
/// Request body for saving glow data.
/// </summary>
public class SaveGlowRequest
{
    [Required]
    public string Data { get; set; } = string.Empty;
}

/// <summary>
/// Controller providing CRUD endpoints for Second Life glow persistence.
/// </summary>
[ApiController]
[Route("api/glow")]
public class GlowController : ControllerBase
{
    private static readonly Regex UuidRegex = new(
        @"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    // Data format: "meta;values" where meta and values are pipe-delimited numbers
    private static readonly Regex DataFormatRegex = new(
        @"^[\d.|]+;[\d.|]+$",
        RegexOptions.Compiled);

    private readonly GlowDbContext _db;
    private readonly ILogger<GlowController> _logger;

    public GlowController(GlowDbContext db, ILogger<GlowController> logger)
    {
        _db = db;
        _logger = logger;
    }

    /// <summary>
    /// Health check endpoint.
    /// GET /api/glow/health
    /// </summary>
    [HttpGet("health")]
    public IActionResult Health()
    {
        return Ok(new { status = "healthy", timestamp = DateTime.UtcNow });
    }

    /// <summary>
    /// Retrieve glow data for a Second Life object by UUID.
    /// GET /api/glow/{objectId}
    /// </summary>
    [HttpGet("{objectId}")]
    public async Task<IActionResult> GetGlow(string objectId)
    {
        if (!IsValidUuid(objectId))
        {
            _logger.LogWarning("GetGlow: Invalid UUID format: {ObjectId}", objectId);
            return BadRequest(new { error = "Invalid object ID format. Expected UUID." });
        }

        try
        {
            var record = await _db.GlowRecords.FindAsync(objectId.ToLowerInvariant());
            if (record == null)
            {
                _logger.LogInformation("GetGlow: No record found for {ObjectId}", objectId);
                return NotFound(new { error = "No glow data found for this object." });
            }

            _logger.LogInformation("GetGlow: Retrieved record for {ObjectId}", objectId);
            return Ok(new
            {
                objectId = record.ObjectId,
                data = record.Data,
                updatedAt = record.UpdatedAt
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "GetGlow: Error retrieving record for {ObjectId}", objectId);
            return StatusCode(500, new { error = "Internal server error." });
        }
    }

    /// <summary>
    /// Save or update glow data for a Second Life object by UUID.
    /// POST /api/glow/{objectId}
    /// Body: { "data": "4|6|8;0.5|0.3|0.0|..." }
    /// </summary>
    [HttpPost("{objectId}")]
    public async Task<IActionResult> SaveGlow(string objectId, [FromBody] SaveGlowRequest request)
    {
        if (!IsValidUuid(objectId))
        {
            _logger.LogWarning("SaveGlow: Invalid UUID format: {ObjectId}", objectId);
            return BadRequest(new { error = "Invalid object ID format. Expected UUID." });
        }

        if (!IsValidDataFormat(request.Data))
        {
            _logger.LogWarning("SaveGlow: Invalid data format for {ObjectId}: {Data}", objectId, request.Data);
            return BadRequest(new { error = "Invalid data format. Expected 'metadata;values' with pipe-delimited numbers." });
        }

        try
        {
            string normalizedId = objectId.ToLowerInvariant();
            var existing = await _db.GlowRecords.FindAsync(normalizedId);

            if (existing != null)
            {
                existing.Data = request.Data;
                existing.UpdatedAt = DateTime.UtcNow;
                _db.GlowRecords.Update(existing);
            }
            else
            {
                var record = new GlowRecord
                {
                    ObjectId = normalizedId,
                    Data = request.Data,
                    UpdatedAt = DateTime.UtcNow
                };
                await _db.GlowRecords.AddAsync(record);
            }

            await _db.SaveChangesAsync();

            _logger.LogInformation("SaveGlow: Saved record for {ObjectId}", objectId);
            return Ok(new
            {
                objectId = normalizedId,
                message = "Glow data saved successfully.",
                updatedAt = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SaveGlow: Error saving record for {ObjectId}", objectId);
            return StatusCode(500, new { error = "Internal server error." });
        }
    }

    /// <summary>
    /// Delete glow data for a Second Life object by UUID.
    /// DELETE /api/glow/{objectId}
    /// </summary>
    [HttpDelete("{objectId}")]
    public async Task<IActionResult> DeleteGlow(string objectId)
    {
        if (!IsValidUuid(objectId))
        {
            _logger.LogWarning("DeleteGlow: Invalid UUID format: {ObjectId}", objectId);
            return BadRequest(new { error = "Invalid object ID format. Expected UUID." });
        }

        try
        {
            string normalizedId = objectId.ToLowerInvariant();
            var record = await _db.GlowRecords.FindAsync(normalizedId);
            if (record == null)
            {
                return NotFound(new { error = "No glow data found for this object." });
            }

            _db.GlowRecords.Remove(record);
            await _db.SaveChangesAsync();

            _logger.LogInformation("DeleteGlow: Deleted record for {ObjectId}", objectId);
            return Ok(new { message = "Glow data deleted successfully." });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "DeleteGlow: Error deleting record for {ObjectId}", objectId);
            return StatusCode(500, new { error = "Internal server error." });
        }
    }

    private static bool IsValidUuid(string value)
    {
        return !string.IsNullOrWhiteSpace(value) && UuidRegex.IsMatch(value);
    }

    private static bool IsValidDataFormat(string data)
    {
        if (string.IsNullOrWhiteSpace(data))
        {
            return false;
        }
        return DataFormatRegex.IsMatch(data);
    }
}
