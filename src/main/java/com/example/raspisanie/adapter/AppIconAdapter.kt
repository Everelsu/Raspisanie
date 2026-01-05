package com.example.raspisanie.adapter

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView
import com.example.raspisanie.R
import com.example.raspisanie.data.PreferencesManager
import com.google.android.material.card.MaterialCardView

class AppIconAdapter(
    private val icons: List<IconItem>,
    private var selectedIcon: String,
    private val onIconSelected: (String) -> Unit
) : RecyclerView.Adapter<AppIconAdapter.IconViewHolder>() {

    data class IconItem(
        val id: String,
        val name: String,
        val iconRes: Int
    )

    class IconViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val card: MaterialCardView = itemView.findViewById(R.id.iconCard)
        val iconPreview: ImageView = itemView.findViewById(R.id.iconPreview)
        val iconName: TextView = itemView.findViewById(R.id.iconName)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): IconViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_app_icon, parent, false)
        return IconViewHolder(view)
    }

    override fun onBindViewHolder(holder: IconViewHolder, position: Int) {
        val iconItem = icons[position]
        val isSelected = iconItem.id == selectedIcon

        holder.iconName.text = iconItem.name
        holder.iconPreview.setImageResource(iconItem.iconRes)

        // Применяем стиль выбранной карточки (как в Telegram)
        if (isSelected) {
            holder.card.strokeWidth = 2
            // Используем цвет акцента темы
            val typedValue = android.util.TypedValue()
            holder.itemView.context.theme.resolveAttribute(android.R.attr.colorAccent, typedValue, true)
            holder.card.strokeColor = typedValue.data
            holder.card.cardElevation = 0f
        } else {
            holder.card.strokeWidth = 0
            holder.card.strokeColor = android.graphics.Color.TRANSPARENT
            holder.card.cardElevation = 0f
        }

        holder.card.setOnClickListener {
            if (!isSelected) {
                val previousPosition = icons.indexOfFirst { it.id == selectedIcon }
                selectedIcon = iconItem.id
                
                // Плавная анимация выбора (как в Telegram)
                holder.card.animate()
                    .scaleX(0.95f)
                    .scaleY(0.95f)
                    .setDuration(100)
                    .withEndAction {
                        holder.card.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .setDuration(150)
                            .setInterpolator(android.view.animation.OvershootInterpolator(1.2f))
                            .start()
                    }
                    .start()
                
                // Обновляем предыдущий и текущий элементы
                if (previousPosition >= 0) {
                    notifyItemChanged(previousPosition)
                }
                notifyItemChanged(position)
                onIconSelected(iconItem.id)
                
                // Haptic feedback
                holder.card.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY)
            }
        }
    }

    override fun getItemCount() = icons.size
}

