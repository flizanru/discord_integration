import discord
from discord.ext import commands, tasks
import mysql.connector
from discord.ui import Button, View
import random
import string
from datetime import datetime, timedelta

db_config = {
    'user': 'USERNAME',
    'password': 'PASSWORD',
    'host': 'IP',
    'database': 'DATABASE'
}

your_guild_id = 0000000000000000000 # guild-id

role_mappings = { # your roles
    'user': '1238882160858107954', 
    'VIP': '1238899909999198219',
    'superadmin': '1238882196127744031'
}

intents = discord.Intents.default()
intents.members = True

bot = commands.Bot(command_prefix="/", intents=intents)

def get_database_connection():
    try:
        return mysql.connector.connect(**db_config)
    except mysql.connector.Error as e:
        print(f"Error connecting to MySQL database: {e}")
        return None

def generate_token(length=6):
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=length))

@tasks.loop(seconds=30)
async def update_roles():
    guild = bot.get_guild(your_guild_id)
    if not guild:
        print(f"Guild with ID {your_guild_id} not found.")
        return

    conn = get_database_connection()
    if not conn:
        return

    cursor = conn.cursor()
    cursor.execute("SELECT discord_id, usergroup FROM tokens WHERE discord_id IS NOT NULL")
    user_records = cursor.fetchall()
    cursor.close()
    conn.close()

    for discord_id, usergroup in user_records:
        try:
            member = await guild.fetch_member(int(discord_id))
        except discord.NotFound:
            print(f"Member with ID {discord_id} not found.")
            continue

        role_id = role_mappings.get(usergroup)
        if role_id:
            new_role = guild.get_role(int(role_id))
            if new_role:
                try:
                    await member.edit(roles=[new_role] + [role for role in member.roles if role.managed])
                    print(f"✅ Updated roles for {member} to include {new_role.name}")
                except discord.Forbidden:
                    print(f"❌ Permission Error: Could not change roles for {member}")
                except discord.HTTPException as e:
                    print(f"❌ HTTP Exception: {e}")
            else:
                print(f"❌ Role ID {role_id} not found in the guild.")
        else:
            print(f"❌ User group '{usergroup}' not recognized or not mapped to a role.")

@tasks.loop(seconds=30)
async def update_nicknames():
    guild = bot.get_guild(your_guild_id)
    if not guild:
        print(f"Guild with ID {your_guild_id} not found.")
        return

    conn = get_database_connection()
    if not conn:
        return

    cursor = conn.cursor()
    cursor.execute("SELECT discord_id, nickname FROM tokens WHERE discord_id IS NOT NULL")
    user_records = cursor.fetchall()
    cursor.close()
    conn.close()

    for discord_id, nickname in user_records:
        try:
            member = await guild.fetch_member(int(discord_id))
        except discord.NotFound:
            print(f"Member with ID {discord_id} not found.")
            continue

        if member.nick != nickname:
            try:
                await member.edit(nick=nickname)
                print(f"✅ Updated nickname for {member} to {nickname}")
            except discord.Forbidden:
                print(f"❌ Permission Error: Could not change nickname for {member}")
            except discord.HTTPException as e:
                print(f"❌ HTTP Exception: {e}")


async def button_callback(button_interaction):
    conn = get_database_connection()
    if not conn:
        await button_interaction.response.send_message("❌ Database connection failed.", ephemeral=True)
        return

    cursor = conn.cursor()
    try:
        if conn.in_transaction:
            conn.commit()

        conn.start_transaction()
        cursor.execute("DELETE FROM tokens WHERE discord_id = %s", (str(button_interaction.user.id),))
        token = generate_token()
        end_time = datetime.now() + timedelta(minutes=5)
        cursor.execute("INSERT INTO tokens (token, discord_id, end_time) VALUES (%s, %s, %s)", (token, str(button_interaction.user.id), end_time))
        conn.commit()

        embed = discord.Embed(title="✅ Синхронизация", description="Мы выпустили для вас токен! 🔑", color=discord.Color.green())
        embed.add_field(name="Token", value=token)
        await button_interaction.response.send_message(embed=embed, ephemeral=True)
    except mysql.connector.Error as e:
        if conn.in_transaction:
            conn.rollback()
        await button_interaction.response.send_message(f"❌ Ошибка при обработке запроса: {str(e)}", ephemeral=True)
    finally:
        cursor.close()
        conn.close()

@bot.slash_command(name="start", description="Начать работу с ботом")
async def start(ctx):
    conn = get_database_connection()
    if not conn:
        await ctx.respond("❌ Database connection failed.", ephemeral=True)
        return

    cursor = conn.cursor()
    cursor.execute("SELECT token, end_time FROM tokens WHERE discord_id = %s AND end_time > NOW()", (str(ctx.author.id),))
    existing_token = cursor.fetchone()

    if existing_token:
        token, end_time = existing_token
        embed = discord.Embed(
            title="⚠️ У вас уже есть токен",
            description=f"У вас уже есть активный токен: **{token}**. Срок его действия истекает в {end_time}.",
            color=discord.Color.orange()
        )
        await ctx.respond(embed=embed, ephemeral=True)
        cursor.close()
        conn.close()
        return

    button = Button(label="Синхронизация", style=discord.ButtonStyle.green, emoji="🔄")
    button.callback = button_callback

    view = View()
    view.add_item(button)
    await ctx.respond("🔍 Нажмите на кнопку для синхронизации:", view=view, ephemeral=True)

@bot.event
async def on_ready():
    print(f'🎉 Logged in as {bot.user}')
    update_roles.start()
    update_nicknames.start()


bot.run("TOKEN")
